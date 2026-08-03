import AppKit
import Darwin
import ServiceManagement
import CoreWLAN
import NetworkMonitorCore

// MARK: - Network Speed Monitor

@MainActor
final class NetworkSpeedMonitor: @preconcurrency NetworkMonitoringService {
    private var previousData: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTimestamp: Date = Date()

    private(set) var downloadSpeed: Double = 0
    private(set) var uploadSpeed: Double = 0
    private(set) var totalRx: UInt64
    private(set) var totalTx: UInt64

    init(totalRx: UInt64 = 0, totalTx: UInt64 = 0) {
        self.totalRx = totalRx
        self.totalTx = totalTx
    }

    func poll() {
        let current = readInterfaceBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTimestamp)
        guard elapsed > 0 else { return }

        var totalRxDiff: UInt64 = 0
        var totalTxDiff: UInt64 = 0

        for (iface, (rx, tx)) in current {
            if let prev = previousData[iface] {
                let rxDiff = rx >= prev.rx ? rx - prev.rx : rx
                let txDiff = tx >= prev.tx ? tx - prev.tx : tx
                totalRxDiff &+= rxDiff
                totalTxDiff &+= txDiff
                totalRx &+= rxDiff
                totalTx &+= txDiff
            }
            previousData[iface] = (rx, tx)
        }

        let currentIfaces = Set(current.keys)
        previousData = previousData.filter { currentIfaces.contains($0.key) }

        downloadSpeed = Double(totalRxDiff) / elapsed
        uploadSpeed = Double(totalTxDiff) / elapsed
        previousTimestamp = now
    }

    private func readInterfaceBytes() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name != "lo0",
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == AF_LINK,
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            {
                let d = data.pointee
                result[name] = (UInt64(d.ifi_ibytes), UInt64(d.ifi_obytes))
            }
            ptr = current.pointee.ifa_next
        }
        return result
    }
}

// MARK: - Per-Process Network Monitor

@MainActor
final class ProcessNetworkMonitor: @preconcurrency ProcessNetworkMonitoringService {
    private var previous: [Int32: (UInt64, UInt64)] = [:]
    private(set) var processSpeeds: [ProcessNetUsage] = []
    private var lastUpdateTime: Date?

    /// 上次发起采样的时间（节流用）
    private var lastPollDate: Date = .distantPast
    /// 采样最小间隔 — nettop 单次采样约 1 秒，3 秒间隔避免频繁 fork 子进程
    private static let pollInterval: TimeInterval = 3.0
    /// 后台采样队列 — nettop 子进程在此队列执行，不阻塞主线程
    private let workQueue = DispatchQueue(label: "com.networkmonitor.process-poll", qos: .utility)

    func poll() {
        // 节流：主线程每秒调用，但真正采样最多每 3 秒一次
        let now = Date()
        guard now.timeIntervalSince(lastPollDate) >= Self.pollInterval else { return }
        lastPollDate = now

        let previousSnapshot = previous
        let lastUpdate = lastUpdateTime
        let defaultElapsed = Self.pollInterval

        workQueue.async { [weak self] in
            // 后台执行 nettop（约 1 秒），主线程不阻塞
            guard let snapshot = try? runNettopSnapshot(), !snapshot.isEmpty else { return }

            let sampledAt = Date()
            let elapsed: Double
            if let last = lastUpdate {
                elapsed = sampledAt.timeIntervalSince(last)
            } else {
                elapsed = defaultElapsed
            }

            var speeds: [ProcessNetUsage] = []
            var nextPrevious: [Int32: (UInt64, UInt64)] = previousSnapshot
            for current in snapshot {
                if let prev = nextPrevious[current.pid] {
                    let deltaIn = current.bytesIn >= prev.0 ? current.bytesIn - prev.0 : 0
                    let deltaOut = current.bytesOut >= prev.1 ? current.bytesOut - prev.1 : 0
                    let speedIn = Double(deltaIn) / elapsed
                    let speedOut = Double(deltaOut) / elapsed
                    if speedIn > 0 || speedOut > 0 {
                        speeds.append(ProcessNetUsage(
                            name: current.name, pid: current.pid,
                            bytesIn: UInt64(speedIn), bytesOut: UInt64(speedOut)
                        ))
                    }
                }
                nextPrevious[current.pid] = (current.bytesIn, current.bytesOut)
            }
            speeds.sort(by: { $0.total > $1.total })

            let currentPids = Set(snapshot.map { $0.pid })
            nextPrevious = nextPrevious.filter { currentPids.contains($0.key) }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.previous = nextPrevious
                self.lastUpdateTime = sampledAt
                self.processSpeeds = speeds
            }
        }
    }
}
