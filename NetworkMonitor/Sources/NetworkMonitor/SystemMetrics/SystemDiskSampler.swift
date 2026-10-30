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

    /// 读取所有块存储驱动的累计计数
    ///
    /// key 为 IORegistryEntryID：多实例（内置盘 + 外置盘）的枚举顺序不保证稳定，
    /// 必须按注册表 ID 配对，禁止按数组下标配对（实测下标配对会得到负速率）。
    ///
    /// 六个键取自**同一个** Statistics 字典（一次 IOKit 调用即可全取，无需二次遍历）：
    /// "Bytes (Read)"/"Bytes (Write)"、"Operations (Read)"/"Operations (Write)"、
    /// "Total Time (Read)"/"Total Time (Write)"（注意 Total Time 单位是**纳秒**）。
    /// 实测 macOS 27 / M1 Pro 上 IOBlockStorageDriver 的 Statistics 六键齐备。
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
                table[entryID] = DiskTransfer(readBytes: counter(statistics, "Bytes (Read)"),
                                              writeBytes: counter(statistics, "Bytes (Write)"),
                                              readOperations: counter(statistics, "Operations (Read)"),
                                              writeOperations: counter(statistics, "Operations (Write)"),
                                              readTotalTime: counter(statistics, "Total Time (Read)"),
                                              writeTotalTime: counter(statistics, "Total Time (Write)"))
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return table.isEmpty ? nil : table
    }

    /// 从 Statistics 字典取一个累计计数器；缺键或非数字按 0 处理
    ///
    /// 缺键不判失败：不同 macOS 版本 / 虚拟设备可能少给某些键，
    /// 单项缺失只让对应的 IOPS 或繁忙度偏低，不影响读写速率照常展示。
    private static func counter(_ statistics: [String: Any], _ key: String) -> UInt64 {
        (statistics[key] as? NSNumber)?.uint64Value ?? 0
    }

    /// 由两次累计计数表算整机吞吐（速率 + IOPS + 繁忙度）
    ///
    /// 配对与差分全部走 Core 的 SystemMetricsCalculations.diskThroughput（可测试）：
    /// - 无基线（首帧）→ nil：不把「未知」显示成 0；
    /// - 只累加两次都存在的 entryID；某实例消失（拔盘）不计入；
    /// - 累计值倒退（换盘 / 计数器重置）按 0 增量处理，不产生负速率；
    /// - 繁忙度 =（读 + 写服务时间，纳秒 → 秒）/ elapsed，clamp 到 0...1。
    static func throughput(previous: DiskTransferTable?,
                           current: DiskTransferTable,
                           elapsed: TimeInterval) -> DiskThroughput? {
        SystemMetricsCalculations.diskThroughput(previous: previous,
                                                 current: current,
                                                 elapsed: elapsed)
    }
}
