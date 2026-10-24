import Darwin
import Foundation

// MARK: - Socket 收发原语

/// 说明：与主文件同属 `UdpDiscoveryService`，成员可见性放宽为 internal 以便跨文件调用。
extension UdpDiscoveryService {

    // MARK: - Socket

    func startReadSource() {
        guard receiveFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: receiveFD, queue: queue)
        source.setEventHandler { [weak self] in self?.drainReceive() }
        source.resume()
        readSource = source
    }

    /// 打开接收 socket：绑 53318 并加入组播组
    func openReceiveSocket() throws -> Int32 {
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
        // 指定加入的主接口：多网卡时 INADDR_ANY 可能只加到第一个（往往是桥接）接口
        if let primary = getLocalIPAddress() {
            membership.imr_interface.s_addr = inet_addr(primary)
        } else {
            membership.imr_interface.s_addr = INADDR_ANY
        }
        let joinResult = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership,
                                    socklen_t(MemoryLayout<ip_mreq>.size))
        if joinResult != 0 {
            logger.warning("加入组播组 \(DiscoveryMessage.multicastHost) 失败（errno \(errno)），仅依赖广播与单播兜底")
        }
        // 收包路径是 DispatchSourceRead + 循环 recvfrom：必须非阻塞，
        // 否则读到没有待处理报文时 recvfrom 会把整条网络队列挂住（stop/心跳排队等它）
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        return fd
    }

    /// 打开发送 socket：组播 TTL 1 + 允许广播
    func openSendSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw TransferError.discoverySocket(errno: errno) }

        var ttl: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))
        // 关键：多网卡（含桥接/PROMISC 接口）时内核可能选错组播出口，
        // 表现为 sendto 成功但包不出网卡、对端收不到。显式固定到主 IPv4 接口。
        if let primary = getLocalIPAddress() {
            var iface = in_addr()
            inet_pton(AF_INET, primary, &iface)
            let rc = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &iface,
                                socklen_t(MemoryLayout<in_addr>.size))
            if rc == 0 {
                logger.info("组播出口固定为 \(primary)")
            } else {
                logger.warning("固定组播出口失败 errno=\(errno)")
            }
        }
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
    func send(_ data: Data, to host: String) {
        guard sendFD >= 0 else {
            logger.warning("UDP 发送被跳过：发送 socket 未打开（host=\(host)）")
            return
        }
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
            logger.warning("UDP 发送失败 host=\(host) errno=\(errno)")
        }
    }

    /// 关闭收发 socket（幂等；`start()` 失败与 `stop()` 共用）
    func closeSockets() {
        if receiveFD >= 0 {
            close(receiveFD)
            receiveFD = -1
            noteSocketClosed()
        }
        if sendFD >= 0 {
            close(sendFD)
            sendFD = -1
            noteSocketClosed()
        }
    }

    /// 计数 +1（socket 打开成功后调用）
    func noteSocketOpened() {
        socketStateLock.lock()
        openSocketTotal += 1
        socketStateLock.unlock()
    }

    /// 计数 -1（socket 关闭后调用）
    private func noteSocketClosed() {
        socketStateLock.lock()
        openSocketTotal = max(0, openSocketTotal - 1)
        socketStateLock.unlock()
    }
}
