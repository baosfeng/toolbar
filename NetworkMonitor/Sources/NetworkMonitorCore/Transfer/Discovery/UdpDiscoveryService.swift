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
    // 说明：logger、队列与 socket 状态放宽为 internal，供 `UdpDiscoveryService+Socket` 扩展文件使用
    let logger: LoggingService
    /// 已知设备地址记忆（可为空：测试或不启用快速路径）
    private let knownPeers: KnownPeerStore?

    /// 网络收发串行队列
    let queue = DispatchQueue(label: "com.networkmonitor.transfer.discovery")

    // MARK: - 状态

    var receiveFD: Int32 = -1
    var sendFD: Int32 = -1
    var readSource: DispatchSourceRead?
    private var heartbeatTimer: DispatchSourceTimer?
    private var fallbackTasks: [DispatchWorkItem] = []
    private var offerCooldowns: [String: Date] = [:]
    var running = false
    /// socket 计数（只在状态锁内读写，避免测试观测时与网络队列互相等待）
    let socketStateLock = NSLock()
    var openSocketTotal = 0

    // MARK: - 初始化

    public init(identity: LocalIdentity,
                registry: DeviceRegistry,
                knownPeers: KnownPeerStore? = nil,
                logger: LoggingService = AppContext.shared.logger) {
        self.identity = identity
        self.registry = registry
        self.knownPeers = knownPeers
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
                self.noteSocketOpened()
                self.sendFD = try self.openSendSocket()
                self.noteSocketOpened()
            } catch {
                self.logger.error((error as? TransferError)?.message ?? "发现层启动失败：\(error)")
                self.closeSockets()
                return
            }
            self.running = true
            self.logger.info("发现层 socket 就绪：receiveFD=\(self.receiveFD) sendFD=\(self.sendFD)")
            self.startReadSource()
            self.startTimers()
            // 快速路径：先单播探测上次见过的设备，命中即入表，不必等组播降级链
            self.probeKnownHosts()
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
            // 接收 + 发送两个 fd 一并关闭；只关发送 fd 会让 53318 端口一直被占用
            self.closeSockets()
            self.logger.info("发现层已停止")
        }
    }

    /// 当前打开的 socket 数量 — 供测试观测 fd 泄漏
    ///
    /// 只走独立状态锁，不 `queue.sync`：网络队列可能被阻塞的收发调用占用，
    /// 观测接口不能因此让测试卡死。
    public var openSocketCount: Int {
        socketStateLock.lock()
        defer { socketStateLock.unlock() }
        return openSocketTotal
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
            self.probeKnownHosts()
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

    /// 对上次见过的地址逐个单播探测（快速路径）
    private func probeKnownHosts() {
        guard let knownPeers else { return }
        let hosts = knownPeers.knownHosts()
        guard !hosts.isEmpty else { return }
        logger.info("优先探测已知设备 \(hosts.count) 个：\(hosts.joined(separator: ", "))")
        for host in hosts { sendDiscover(to: host) }
    }

    /// 发送主动查询
    private func sendDiscover(to host: String) {
        guard running, sendFD >= 0 else { return }
        guard let data = DiscoveryMessage.discover().encoded() else { return }
        send(data, to: host)
    }

    /// 处理收到的报文：公告类写设备表，查询类单播应答
    func handleReceive(_ data: Data, from ip: String) {
        guard let message = DiscoveryMessage.decode(data) else { return }
        switch message.type {
        case .announce, .offer:
            // 本机组播回环会收到自己的公告：既不进设备表，也不记为已知地址
            guard message.deviceId != identity.deviceId else { return }
            registry.upsert(message: message, ip: ip)
            knownPeers?.remember(deviceId: message.deviceId, ip: ip)
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
}
