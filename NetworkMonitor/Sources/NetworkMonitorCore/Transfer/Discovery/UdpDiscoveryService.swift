import Darwin
import Foundation

// MARK: - UDP 发现服务

/// UDP 发现服务 — 组播公告 + 广播 `/24` 兜底 + 心跳 + 离线判定
///
/// 实现说明：
/// - 收发走 BSD socket（`Network.framework` 不暴露组播入组接口），仍属系统框架、零第三方依赖
/// - 接收 socket 加入组播组 `239.255.77.77:53318`，发送 socket 打开广播与组播 TTL
/// - 所有网络操作串行在内部队列上，回调统一经 `DeviceRegistry` 投递主队列
/// - 本地网络权限被拒时无法建立接收通道：`start()` 失败会通过日志给出明确诊断，而不是静默空列表
public final class UdpDiscoveryService: @unchecked Sendable {

    // MARK: - 依赖

    private let identity: LocalIdentity
    private let registry: DeviceRegistry
    private let logger: LoggingService

    /// 网络收发串行队列
    private let queue = DispatchQueue(label: "com.networkmonitor.transfer.discovery")

    // MARK: - 状态

    private var receiveFD: Int32 = -1
    private var sendFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var heartbeatTimer: DispatchSourceTimer?
    private var fallbackTasks: [DispatchWorkItem] = []
    private var offerCooldowns: [String: Date] = [:]
    private var running = false

    // MARK: - 初始化

    public init(identity: LocalIdentity,
                registry: DeviceRegistry,
                logger: LoggingService = AppContext.shared.logger) {
        self.identity = identity
        self.registry = registry
        self.logger = logger
    }

    deinit {
        // 兜底释放：正常路径由 stop() 关闭
        if receiveFD >= 0 { close(receiveFD) }
        if sendFD >= 0 { close(sendFD) }
    }

    // MARK: - 生命周期

    /// 启动发现：打开 socket → 连发 3 次公告 → 进入 5s 心跳
    public func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            do {
                self.receiveFD = try self.openReceiveSocket()
                self.sendFD = try self.openSendSocket()
            } catch {
                self.logger.error((error as? TransferError)?.message ?? "发现层启动失败：\(error)")
                self.closeSockets()
                return
            }
            self.running = true
            self.startReadSource()
            self.startTimers()
            // 启动连发 3 次，间隔 500ms
            for index in 0..<DiscoveryMessage.startupBurstCount {
                let delay = Double(index) * DiscoveryMessage.startupBurstInterval
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.announce()
                }
            }
            self.logger.info("发现层已启动：设备 \(self.identity.deviceId) 端口 \(self.identity.port)，UDP \(DiscoveryMessage.udpPort)")
        }
    }

    /// 停止发现并释放端口
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.fallbackTasks.forEach { $0.cancel() }
            self.fallbackTasks.removeAll()
            self.readSource?.cancel()
            self.readSource = nil
            self.heartbeatTimer?.cancel()
            self.heartbeatTimer = nil
            let receive = self.receiveFD
            self.receiveFD = -1
            if receive >= 0 { close(receive) }
            self.closeSockets()
            self.logger.info("发现层已停止")
        }
    }

    /// 立即发布一次公告（心跳以外的主动通告）
    public func announceNow() {
        queue.async { [weak self] in self?.announce() }
    }

    /// 手动刷新：组播 `discover` → 3s 无新增转广播 → 再 3s 转 `/24` 单播
    public func refreshDiscovery() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.cancelFallbackTasks()
            let baseline = self.onlineCount()
            self.sendDiscover(to: DiscoveryMessage.multicastHost)

            self.scheduleFallback(delay: 3) { [weak self] in
                guard let self, self.onlineCount() <= baseline else { return }
                self.logger.info("组播无应答，降级广播 discover")
                self.sendDiscover(to: "255.255.255.255")
            }
            self.scheduleFallback(delay: 6) { [weak self] in
                guard let self, self.onlineCount() <= baseline else { return }
                self.logger.info("广播无应答，降级 /24 单播扫描")
                self.scanSubnet()
            }
        }
    }

    // MARK: - 收发

    /// 组播发送公告（携带本机身份与 HTTP 端口）
    private func announce() {
        guard running, sendFD >= 0 else { return }
        guard let data = DiscoveryMessage.announce(identity: identity).encoded() else { return }
        send(data, to: DiscoveryMessage.multicastHost)
    }

    /// 发送主动查询
    private func sendDiscover(to host: String) {
        guard running, sendFD >= 0 else { return }
        guard let data = DiscoveryMessage.discover().encoded() else { return }
        send(data, to: host)
    }

    /// 处理收到的报文：公告类写设备表，查询类单播应答
    private func handleReceive(_ data: Data, from ip: String) {
        guard let message = DiscoveryMessage.decode(data) else { return }
        switch message.type {
        case .announce, .offer:
            registry.upsert(message: message, ip: ip)
        case .discover:
            replyOffer(to: ip)
        }
    }

    /// 单播应答 `discover`（同一来源 IP 2s 内只回一次）
    private func replyOffer(to ip: String) {
        let now = Date()
        if let last = offerCooldowns[ip], now.timeIntervalSince(last) < DiscoveryMessage.offerCooldown {
            return
        }
        offerCooldowns[ip] = now
        // 冷却表按需清理，避免长时间运行后无限增长
        if offerCooldowns.count > 64 {
            offerCooldowns = offerCooldowns.filter { now.timeIntervalSince($0.value) < DiscoveryMessage.offerCooldown * 2 }
        }
        guard let data = DiscoveryMessage.announce(identity: identity, kind: .offer).encoded() else { return }
        send(data, to: ip)
    }

    /// `/24` 单播扫描（分批发，批间隔 = 单 IP 超时）
    private func scanSubnet() {
        guard let localIP = getLocalIPAddress() else {
            logger.warning("/24 扫描跳过：未取到 en0/en1 的 IPv4 地址")
            return
        }
        let hosts = SubnetScan.hosts(inSubnetOf: localIP)
        guard !hosts.isEmpty else {
            logger.warning("/24 扫描跳过：本机地址 \(localIP) 不是合法 IPv4")
            return
        }
        let batches = SubnetScan.batches(hosts)
        logger.info("开始 /24 扫描：本机 \(localIP)，共 \(hosts.count) 个地址、\(batches.count) 批")
        for (index, batch) in batches.enumerated() {
            let delay = Double(index) * SubnetScan.batchInterval
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.running else { return }
                for host in batch { self.sendDiscover(to: host) }
            }
        }
    }

    /// 在线设备数（兜底分级判据）
    private func onlineCount() -> Int {
        registry.snapshot().filter(\.isOnline).count
    }

    // MARK: - 定时器

    private func startTimers() {
        let heartbeat = DispatchSource.makeTimerSource(queue: queue)
        heartbeat.schedule(deadline: .now() + DiscoveryMessage.heartbeatInterval,
                           repeating: DiscoveryMessage.heartbeatInterval)
        heartbeat.setEventHandler { [weak self] in
            guard let self else { return }
            self.announce()
            // 心跳同时推进存活状态：15s 离线、60s 移除
            self.registry.applyLiveness()
        }
        heartbeat.resume()
        heartbeatTimer = heartbeat
    }

    private func scheduleFallback(delay: TimeInterval, action: @escaping @Sendable () -> Void) {
        let item = DispatchWorkItem(block: action)
        fallbackTasks.append(item)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelFallbackTasks() {
        fallbackTasks.forEach { $0.cancel() }
        fallbackTasks.removeAll()
    }

    // MARK: - Socket

    private func startReadSource() {
        guard receiveFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: receiveFD, queue: queue)
        source.setEventHandler { [weak self] in self?.drainReceive() }
        source.resume()
        readSource = source
    }

    /// 打开接收 socket：绑 53318 并加入组播组
    private func openReceiveSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw TransferError.discoverySocket(errno: errno) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = DiscoveryMessage.udpPort.bigEndian
        address.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw TransferError.discoveryBind(errno: errno)
        }

        // 加入组播组；失败不致命（广播与单播兜底仍可用），但记录告警
        var membership = ip_mreq()
        membership.imr_multiaddr.s_addr = inet_addr(DiscoveryMessage.multicastHost)
        membership.imr_interface.s_addr = INADDR_ANY
        let joinResult = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership,
                                    socklen_t(MemoryLayout<ip_mreq>.size))
        if joinResult != 0 {
            logger.warning("加入组播组 \(DiscoveryMessage.multicastHost) 失败（errno \(errno)），仅依赖广播与单播兜底")
        }
        return fd
    }

    /// 打开发送 socket：组播 TTL 1 + 允许广播
    private func openSendSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw TransferError.discoverySocket(errno: errno) }

        var ttl: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// 从内核缓冲读取全部待处理报文（非阻塞退化为 EAGAIN 即止）
    private func drainReceive() {
        var buffer = [UInt8](repeating: 0, count: 65_507)
        while running, receiveFD >= 0 {
            var address = sockaddr_in()
            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    buffer.withUnsafeMutableBytes { bytes in
                        recvfrom(receiveFD, bytes.baseAddress, bytes.count, 0, sockaddrPointer, &addressLength)
                    }
                }
            }
            guard count > 0 else { return }
            let data = Data(buffer.prefix(count))
            let ip = String(cString: inet_ntoa(address.sin_addr))
            handleReceive(data, from: ip)
        }
    }

    /// 发送一个 UDP 报文（失败仅记录，不中断心跳）
    private func send(_ data: Data, to host: String) {
        guard sendFD >= 0 else { return }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = DiscoveryMessage.udpPort.bigEndian
        address.sin_addr.s_addr = inet_addr(host)

        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(sendFD, bytes.baseAddress, data.count, 0, $0,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            logger.debug("UDP 发送失败 host=\(host) errno=\(errno)")
        }
    }

    private func closeSockets() {
        if sendFD >= 0 {
            close(sendFD)
            sendFD = -1
        }
    }
}
