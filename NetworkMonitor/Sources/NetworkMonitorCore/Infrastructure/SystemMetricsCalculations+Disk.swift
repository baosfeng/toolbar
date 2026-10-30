import Foundation

// MARK: - 磁盘差分（拆出主文件）
//
// 拆出原因：主文件已到 13.4 KiB，逼近单文件 15360 字节上限；磁盘差分的口径
// （累计计数器 → 每秒值 / 繁忙度）与 CPU、GPU 相互独立，按 SRP 独立成文件。
// 跨文件访问把私有公用实现 perSecond 放宽为 internal（同模块内除本文件无其他调用方）。

// MARK: - 磁盘取值类型

/// 单块块存储设备的累计计数（IOBlockStorageDriver 的 Statistics 快照）
///
/// 单位：字节 / 次 / 纳秒。差分与配对在 SystemMetricsCalculations 中完成，
/// 采样器只负责按注册表 entryID 填这张表。
public struct DiskIOCounters: Sendable, Equatable {
    /// 累计读取字节
    public let readBytes: UInt64
    /// 累计写入字节
    public let writeBytes: UInt64
    /// 累计读操作数（Statistics 的 "Operations (Read)"）
    public let readOperations: UInt64
    /// 累计写操作数（Statistics 的 "Operations (Write)"）
    public let writeOperations: UInt64
    /// 累计读服务时间（纳秒；Statistics 的 "Total Time (Read)"）
    public let readTotalTime: UInt64
    /// 累计写服务时间（纳秒；Statistics 的 "Total Time (Write)"）
    public let writeTotalTime: UInt64

    public init(readBytes: UInt64 = 0,
                writeBytes: UInt64 = 0,
                readOperations: UInt64 = 0,
                writeOperations: UInt64 = 0,
                readTotalTime: UInt64 = 0,
                writeTotalTime: UInt64 = 0) {
        self.readBytes = readBytes
        self.writeBytes = writeBytes
        self.readOperations = readOperations
        self.writeOperations = writeOperations
        self.readTotalTime = readTotalTime
        self.writeTotalTime = writeTotalTime
    }
}

/// 整机单帧磁盘吞吐差分结果
///
/// 全部字段都是本帧的瞬时值：速率（字节/秒）、IOPS（次/秒）、繁忙度（0...1）。
public struct DiskThroughput: Sendable, Equatable {
    /// 读取速率（字节/秒）
    public let readBytesPerSecond: Double
    /// 写入速率（字节/秒）
    public let writeBytesPerSecond: Double
    /// 读 IOPS（次/秒）
    public let readIOPS: Double
    /// 写 IOPS（次/秒）
    public let writeIOPS: Double
    /// 繁忙度（0...1）；时间差非法时为 nil
    public let busyFraction: Double?

    public init(readBytesPerSecond: Double,
                writeBytesPerSecond: Double,
                readIOPS: Double,
                writeIOPS: Double,
                busyFraction: Double?) {
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.readIOPS = readIOPS
        self.writeIOPS = writeIOPS
        self.busyFraction = busyFraction
    }
}

// MARK: - 磁盘差分

extension SystemMetricsCalculations {

    /// 单实例累计字节差换算速率（字节/秒）
    ///
    /// - 时间差 ≤ 0 或非有限 → nil（不除零）；
    /// - 累计值倒退（换盘 / 计数器重置）→ nil（不返回负速率）；
    /// - 无基线（首帧）由调用方直接跳过，本函数不处理 nil 基线。
    public static func bytesPerSecond(previous: UInt64,
                                      current: UInt64,
                                      elapsed: TimeInterval) -> Double? {
        perSecond(previous: previous, current: current, elapsed: elapsed)
    }

    /// 单实例累计次数差换算频率（次/秒），用于磁盘 IOPS
    ///
    /// 与 bytesPerSecond 同构：只换语义（字节 → 操作数），边界口径完全一致。
    public static func operationsPerSecond(previous: UInt64,
                                           current: UInt64,
                                           elapsed: TimeInterval) -> Double? {
        perSecond(previous: previous, current: current, elapsed: elapsed)
    }

    /// 累计计数器单路增量；倒退（计数器重置 / 换设备）按 0 处理，绝不产生负值
    public static func counterDelta(previous: UInt64, current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    /// 磁盘繁忙度 =（读服务时间 + 写服务时间）/ 采样间隔，clamp 到 0...1
    ///
    /// IOBlockStorageDriver 的 "Total Time (Read/Write)" 单位是**纳秒**，
    /// 因此先除以 1e9 换成秒，再与 elapsed（秒）相比。
    ///
    /// - 时间差 ≤ 0 或非有限 → nil（不除零）；
    /// - 服务时间累计值倒退由调用方用 counterDelta 先行归零，本函数不做负值兜底；
    /// - 结果按 0...1 封顶：多块盘并行时服务时间之和可超过采样间隔，
    ///   但「繁忙度」的百分比语义上限是 100%，超出部分不再有意义。
    public static func busyFraction(readNanoseconds: UInt64,
                                    writeNanoseconds: UInt64,
                                    elapsed: TimeInterval) -> Double? {
        guard elapsed > 0, elapsed.isFinite else { return nil }
        let nanosecondsPerSecond = 1_000_000_000.0
        let busySeconds = (Double(readNanoseconds) + Double(writeNanoseconds)) / nanosecondsPerSecond
        guard busySeconds.isFinite else { return nil }
        return min(max(busySeconds / elapsed, 0), 1)
    }

    /// 由两次累计计数表算整机磁盘吞吐（速率 + IOPS + 繁忙度）
    ///
    /// 入参是「注册表 entryID → 单盘累计计数」的字典，配对直接在字典键上完成：
    /// 多实例（内置盘 + 外置盘）的枚举顺序不保证稳定，按下标配对会算出负速率，
    /// 因此配对逻辑放在 Core 里以键为准，采样器只负责读原始数据。
    ///
    /// 边界约定：
    /// - 无基线（首帧）或时间差 ≤ 0 或当前表为空 → nil，由调用方写成 nil 而不是 0；
    /// - 只累加两次都存在的 entryID：某实例消失（拔盘）不计入；一个都配不上 → nil；
    /// - 单盘累计值倒退（计数器重置）按 0 增量处理，不产生负速率 / 负繁忙度；
    /// - 繁忙度把读、写服务时间（纳秒）相加后除以 elapsed，并 clamp 到 0...1。
    public static func diskThroughput(previous: [UInt64: DiskIOCounters]?,
                                      current: [UInt64: DiskIOCounters]?,
                                      elapsed: TimeInterval) -> DiskThroughput? {
        guard let previous, let current, !current.isEmpty else { return nil }
        guard elapsed > 0, elapsed.isFinite else { return nil }

        var readBytes = 0.0
        var writeBytes = 0.0
        var readOperations = 0.0
        var writeOperations = 0.0
        var readNanoseconds: UInt64 = 0
        var writeNanoseconds: UInt64 = 0
        var paired = false

        for (entryID, transfer) in current {
            guard let baseline = previous[entryID] else { continue }
            paired = true
            readBytes += bytesPerSecond(previous: baseline.readBytes,
                                        current: transfer.readBytes,
                                        elapsed: elapsed) ?? 0
            writeBytes += bytesPerSecond(previous: baseline.writeBytes,
                                         current: transfer.writeBytes,
                                         elapsed: elapsed) ?? 0
            readOperations += operationsPerSecond(previous: baseline.readOperations,
                                                  current: transfer.readOperations,
                                                  elapsed: elapsed) ?? 0
            writeOperations += operationsPerSecond(previous: baseline.writeOperations,
                                                   current: transfer.writeOperations,
                                                   elapsed: elapsed) ?? 0
            readNanoseconds += counterDelta(previous: baseline.readTotalTime,
                                            current: transfer.readTotalTime)
            writeNanoseconds += counterDelta(previous: baseline.writeTotalTime,
                                             current: transfer.writeTotalTime)
        }
        guard paired else { return nil }

        return DiskThroughput(readBytesPerSecond: readBytes,
                              writeBytesPerSecond: writeBytes,
                              readIOPS: readOperations,
                              writeIOPS: writeOperations,
                              busyFraction: busyFraction(readNanoseconds: readNanoseconds,
                                                         writeNanoseconds: writeNanoseconds,
                                                         elapsed: elapsed))
    }

    /// 累计差 / 时间差 的共用实现（字节速率与 IOPS 同构，只有语义不同）
    ///
    /// internal 而非 private：本文件的 bytesPerSecond / operationsPerSecond 都调用它，
    /// 同模块内没有其他调用方。
    static func perSecond(previous: UInt64,
                          current: UInt64,
                          elapsed: TimeInterval) -> Double? {
        guard elapsed > 0, elapsed.isFinite else { return nil }
        guard current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }
}
