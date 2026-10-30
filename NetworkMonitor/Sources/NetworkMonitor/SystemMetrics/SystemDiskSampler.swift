import Darwin
import Foundation
import IOKit
import NetworkMonitorCore

// MARK: - 磁盘采样

/// 磁盘采样 — 容量用 statfs，读写速率用 IOBlockStorageDriver 的 Statistics 差分
enum SystemDiskSampler {

    /// 根卷容量
    ///
    /// f_bavail 是非特权进程可用块数（与「关于本机」的可用空间一致），
    /// used = total - available；statfs 失败或总量为 0 时返回 nil。
    static func capacity() -> (used: UInt64, total: UInt64)? {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return nil }
        let blockSize = UInt64(stats.f_bsize)
        guard blockSize > 0, stats.f_blocks > 0 else { return nil }
        let total = UInt64(stats.f_blocks) &* blockSize
        let available = UInt64(stats.f_bavail) &* blockSize
        return (total > available ? total - available : 0, total)
    }

    /// 读取所有块存储驱动的累计读写字节
    ///
    /// key 为 IORegistryEntryID：多实例（内置盘 + 外置盘）的枚举顺序不保证稳定，
    /// 必须按注册表 ID 配对，禁止按数组下标配对（实测下标配对会得到负速率）。
    static func transfers() -> DiskTransferTable? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                  IOServiceMatching("IOBlockStorageDriver"),
                                                  &iterator)
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var table = DiskTransferTable()
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS,
               let property = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString,
                                                              kCFAllocatorDefault, 0),
               let statistics = property.takeRetainedValue() as? [String: Any] {
                let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                let write = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                table[entryID] = DiskTransfer(readBytes: read, writeBytes: write)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return table.isEmpty ? nil : table
    }

    /// 由两次累计量算读写速率
    ///
    /// - 无基线（首帧）→ nil：不把「未知」显示成 0；
    /// - 只累加两次都存在的 entryID；某实例消失（拔盘）不计入；
    /// - 单实例换算走 Core 的 SystemMetricsCalculations.bytesPerSecond：
    ///   时间差 ≤ 0 与该实例累计值倒退都返回 nil（不产生负速率），该实例本帧跳过。
    static func rates(previous: DiskTransferTable?,
                      current: DiskTransferTable,
                      elapsed: TimeInterval) -> (read: Double, write: Double)? {
        guard let previous, elapsed > 0, !current.isEmpty else { return nil }
        var readTotal = 0.0
        var writeTotal = 0.0
        var paired = false
        for (entryID, transfer) in current {
            guard let baseline = previous[entryID] else { continue }
            paired = true
            if let read = SystemMetricsCalculations.bytesPerSecond(previous: baseline.readBytes,
                                                                   current: transfer.readBytes,
                                                                   elapsed: elapsed) {
                readTotal += read
            }
            if let write = SystemMetricsCalculations.bytesPerSecond(previous: baseline.writeBytes,
                                                                    current: transfer.writeBytes,
                                                                    elapsed: elapsed) {
                writeTotal += write
            }
        }
        guard paired else { return nil }
        return (readTotal, writeTotal)
    }
}
