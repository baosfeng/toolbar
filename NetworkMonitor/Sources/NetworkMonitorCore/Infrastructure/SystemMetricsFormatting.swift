import Foundation

// MARK: - 系统指标展示口径（纯逻辑）

/// 系统监控面板的取数口径 — 不依赖 AppKit，供菜单栏 / 面板 / TestRunner 共用
///
/// 所有函数都是纯函数：入参越界、非法（NaN / 无穷 / 负值 / 0 分母）一律给出
/// 明确定义的结果，不 crash、不返回 NaN。
public enum SystemMetricsFormatting {

    // MARK: 百分比

    /// 比例（0...1）格式化成整数百分比文本
    ///
    /// - 负数与非有限值（NaN / ±无穷）→ "0%"；
    /// - 大于 1 的比例按 100% 封顶（避免 UI 出现 120% 这类越界读数）；
    /// - 四舍五入到整数：0.005 → "1%"，0.004 → "0%"。
    public static func percentText(_ ratio: Double) -> String {
        let clamped = clampedUnit(ratio)
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }

    // MARK: 字节速率

    /// 字节速率格式化：B/KB/MB/GB/TH/s，K 及以上保留 1 位小数
    ///
    /// - nil（不可得）→ "—"；
    /// - 0 → "0 B/s"；512 → "512 B/s"（B 级取整，不带小数）；
    /// - 1536 → "1.5 KB/s"；负数按绝对值处理（差分溢出不应显示成负速率）。
    public static func byteRateText(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite else { return "—" }
        let value = abs(bytesPerSecond)
        if value < 1_024 {
            return "\(Int(value.rounded())) B/s"
        }
        let units: [(threshold: Double, divisor: Double, suffix: String)] = [
            (1_099_511_627_776, 1_099_511_627_776, "TB/s"),
            (1_073_741_824, 1_073_741_824, "GB/s"),
            (1_048_576, 1_048_576, "MB/s"),
            (1_024, 1_024, "KB/s"),
        ]
        guard let unit = units.first(where: { value >= $0.threshold }) else {
            return "\(Int(value.rounded())) B/s"
        }
        return String(format: "%.1f %@", value / unit.divisor, unit.suffix)
    }

    // MARK: 容量

    /// 容量占比（0...1）；总量为 0 或非法时返回 0，已用超过总量时封顶 1
    public static func capacityRatio(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }

    // MARK: 每核 P/E 分组

    /// 每核利用率按 P / E 分组切片
    ///
    /// 顺序实测（macOS 27 / M1 Pro，ioreg -p IODeviceTree 的 cpu0@0…cpu9@203）：
    /// 逻辑 CPU 0、1 是 E 核（cluster-type = "E"），2…9 是 P 核（cluster-type = "P"），
    /// 即「能效核在前、性能核在后」，与 sysctl 的 perflevel 编号方向相反。
    /// 因此前 efficiencyCores 个算 E 核，其后 performanceCores 个算 P 核。
    ///
    /// 边界：perCore 为空、P/E 数量为 0 或负数、P+E 超过实际核数时，
    /// 只按实际可切分数量返回，绝不越界。
    public static func splitCores(perCore: [Double],
                                  performanceCores: Int,
                                  efficiencyCores: Int) -> (performance: [Double], efficiency: [Double]) {
        guard !perCore.isEmpty else { return ([], []) }
        let effCount = min(max(efficiencyCores, 0), perCore.count)
        let remaining = perCore.count - effCount
        let perfCount = min(max(performanceCores, 0), remaining)
        let efficiency = Array(perCore.prefix(effCount))
        let performance = Array(perCore.dropFirst(effCount).prefix(perfCount))
        return (performance, efficiency)
    }

    /// 把 0...1 之外的值收敛到单位区间；非有限值按 0 处理
    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - 环形历史缓冲

/// 近期系统指标快照的固定容量环形缓冲
///
/// 采样周期 1 秒、容量 60 时即「最近一分钟」的历史，供趋势图与峰值统计使用。
/// 值类型：append 为 mutating，可在任意隔离域内安全使用。
public struct SystemMetricsHistory: Sendable {

    /// 容量（至少为 1）
    public let capacity: Int
    /// 环形存储（未写满时按时间正序；写满后按下标环绕）
    private var buffer: [SystemMetricsSnapshot] = []
    /// 下一次覆盖写入的下标
    private var writeIndex = 0

    public init(capacity: Int = 60) {
        self.capacity = max(1, capacity)
    }

    /// 当前条数（不超过容量）
    public var count: Int { buffer.count }

    /// 是否为空
    public var isEmpty: Bool { buffer.isEmpty }

    /// 追加一条快照；写满后覆盖最旧的一条
    public mutating func append(_ snapshot: SystemMetricsSnapshot) {
        if buffer.count < capacity {
            buffer.append(snapshot)
        } else {
            buffer[writeIndex] = snapshot
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    /// 按时间正序返回全部快照（最旧在前、最新在后）
    public var values: [SystemMetricsSnapshot] {
        guard buffer.count == capacity, writeIndex != 0 else { return buffer }
        return Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
    }

    /// 历史中的最高 CPU 总利用率；没有任何 CPU 数据时为 nil
    public var maxCPUUsage: Double? {
        values.compactMap { $0.cpu?.totalUsage }.max()
    }

    /// 历史中的最高内存占用比例；没有任何内存数据时为 nil
    public var maxMemoryRatio: Double? {
        values.compactMap { snapshot -> Double? in
            guard let memory = snapshot.memory, memory.total > 0 else { return nil }
            return Double(memory.used) / Double(memory.total)
        }.max()
    }
}
