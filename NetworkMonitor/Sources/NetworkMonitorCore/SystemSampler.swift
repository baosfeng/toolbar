@preconcurrency import Darwin
import Foundation

/// 系统采样器：定时采集 CPU、内存和网络数据
/// 每60秒进行一次完整采样，写入数据库
public final class SystemSampler {

    // MARK: - 属性

    private let database: DatabaseManager
    private var timer: DispatchSourceTimer?

    /// CPU 采样 — 上次的 ticks 快照
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, total: UInt64)?

    /// 网络采样 — 上次的接口字节快照
    private var previousNetData: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousNetTime: Date = Date()

    private let sampleInterval: TimeInterval = 60

    // MARK: - 初始化

    public init(database: DatabaseManager) {
        self.database = database
    }

    deinit {
        stop()
    }

    // MARK: - 启动/停止

    /// 启动定时采样
    public func start() {
        // 先采集一次初始快照
        previousCPUTicks = readCPUTicks()
        previousNetData = readInterfaceBytes()
        previousNetTime = Date()

        // 启动定时器
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + sampleInterval, repeating: sampleInterval)
        t.setEventHandler { [weak self] in
            self?.sample()
        }
        t.resume()
        timer = t

        print("📊 SystemSampler 已启动 — 每60秒采样一次")
    }

    /// 停止定时采样
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - 采样

    /// 执行一次完整采样
    public func sample() {
        let timestamp = Date().timeIntervalSince1970
        let cpuUsage = sampleCPU()
        let memoryInfo = sampleMemory()
        let (netRx, netTx) = sampleNetwork()

        // 写入数据库
        database.writeSystemSample(
            timestamp: timestamp,
            cpuUsage: cpuUsage,
            memoryUsedMB: memoryInfo.usedMB,
            memoryTotalMB: memoryInfo.totalMB,
            networkRx: netRx,
            networkTx: netTx
        )

        print("📊 采样: CPU \(String(format: "%.1f", cpuUsage))% | 内存 \(memoryInfo.usedMB)MB/\(memoryInfo.totalMB)MB | ↑ \(formatBytes(netTx))/s ↓ \(formatBytes(netRx))/s")
    }

    // MARK: - CPU 采样

    private func readCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, total: UInt64) {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return (0, 0, 0, 1)
        }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0

        let count = Int(numCPUs)
        let data = UnsafeBufferPointer(start: info, count: Int(cpuInfoCount))

        for i in 0..<count {
            let offset = i * Int(CPU_STATE_MAX)
            guard offset + Int(CPU_STATE_MAX) <= data.count else { continue }
            user  += UInt64(data[offset + Int(CPU_STATE_USER)])
            system += UInt64(data[offset + Int(CPU_STATE_SYSTEM)])
            idle  += UInt64(data[offset + Int(CPU_STATE_IDLE)])
        }

        return (user, system, idle, user + system + idle)
    }

    /// 计算 CPU 使用率（百分比）
    private func sampleCPU() -> Double {
        let current = readCPUTicks()

        guard let previous = previousCPUTicks else {
            previousCPUTicks = current
            return 0
        }

        let totalDiff = current.total - previous.total
        guard totalDiff > 0 else { return 0 }

        let idleDiff = current.idle - previous.idle
        let used = Double(totalDiff - idleDiff) / Double(totalDiff) * 100.0

        previousCPUTicks = current
        return used
    }

    // MARK: - 内存采样

    private struct MemoryInfo {
        let usedMB: Int
        let totalMB: Int
    }

    private func sampleMemory() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryInfo(usedMB: 0, totalMB: 0)
        }

        // 获取总物理内存
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        // 计算已使用内存 = active + wired + compressed
        let pageSize = UInt64(vm_kernel_page_size)
        let activeBytes = UInt64(stats.active_count) * pageSize
        let wiredBytes = UInt64(stats.wire_count) * pageSize
        let compressedBytes = UInt64(stats.compressor_page_count) * pageSize

        let usedBytes = activeBytes + wiredBytes + compressedBytes

        return MemoryInfo(
            usedMB: Int(usedBytes / 1024 / 1024),
            totalMB: Int(totalBytes / 1024 / 1024)
        )
    }

    // MARK: - 网络采样

    /// 读取网络接口字节数
    private func readInterfaceBytes() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

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

    /// 计算网络速率（字节/秒）
    private func sampleNetwork() -> (rx: UInt64, tx: UInt64) {
        let current = readInterfaceBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousNetTime)
        guard elapsed > 0 else { return (0, 0) }

        var totalRxDiff: UInt64 = 0
        var totalTxDiff: UInt64 = 0

        for (iface, (rx, tx)) in current {
            if let prev = previousNetData[iface] {
                let rxDiff = rx >= prev.rx ? rx - prev.rx : rx
                let txDiff = tx >= prev.tx ? tx - prev.tx : tx
                totalRxDiff &+= rxDiff
                totalTxDiff &+= txDiff
            }
            previousNetData[iface] = (rx, tx)
        }

        // 清理已消失的接口
        let currentIfaces = Set(current.keys)
        previousNetData = previousNetData.filter { currentIfaces.contains($0.key) }
        previousNetTime = now

        // 返回每秒速率
        return (
            rx: UInt64(Double(totalRxDiff) / elapsed),
            tx: UInt64(Double(totalTxDiff) / elapsed)
        )
    }

    // MARK: - 辅助

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)KB" }
        return String(format: "%.1fMB", Double(bytes) / 1024.0 / 1024.0)
    }
}
