import Foundation

// MARK: - 进程榜口径（CPU 榜 / 内存榜）

/// 进程榜维度 — 首屏压力卡与「压力详情」共用同一套切换语义
public enum SystemProcessMetric: String, Sendable, CaseIterable {
    /// CPU 占用降序
    case cpu
    /// 常驻内存降序
    case memory

    /// 榜单标题（≤4 字）
    public var title: String {
        switch self {
        case .cpu: return "CPU 榜"
        case .memory: return "内存榜"
        }
    }
}

/// 进程榜纯口径 — 排序来源、条形刻度与数值文本
///
/// 采样层（`processTopN`）已经按两种维度各排好一份 Top-N；这里只做「选哪份 + 截断 + 刻度」，
/// 保证首屏 Top-2、详情页 Top-10 与榜单切换走的是同一套口径（不会两处各写一份排序）。
public enum SystemProcessBoard {

    /// 按维度取榜单前 `limit` 条
    ///
    /// - snapshot 为 nil（首帧无基线 / 进程不可读）→ 空数组；
    /// - limit ≤ 0 → 空数组；limit 超过榜单长度时按实际条数返回。
    public static func rows(_ snapshot: ProcessResourceSnapshot?,
                            metric: SystemProcessMetric,
                            limit: Int) -> [ProcessResourceUsage] {
        guard let snapshot, limit > 0 else { return [] }
        let source = metric == .cpu ? snapshot.topCPU : snapshot.topMemory
        return Array(source.prefix(limit))
    }

    // MARK: 条形刻度

    /// CPU 榜条形比例（绝对 sqrt 刻度）：`min(1, sqrt(cpuPercent) × 13 / 100)`
    ///
    /// 系数 13 的实测依据（见原型 §39）：27.6% → 68% 条长、10.7% → 43%、3% → 23%、1% → 13%。
    /// k=10 时榜首长态只有 52%，不够醒目；k=13 让常见区间都有足够权重，
    /// 同时 1% 的碎进程仍有 13% 可见。
    public static func cpuBarFraction(_ cpuPercent: Double) -> Double {
        let raw = cpuPercent.isFinite ? max(0, cpuPercent) : 0
        return min(1, max(0, (raw.squareRoot() * 13) / 100))
    }

    /// 内存榜条形比例（线性）：常驻内存 / 物理内存；总量 0 → 0（不产生除零）
    public static func memoryBarFraction(residentBytes: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(residentBytes) / Double(totalBytes))
    }

    // MARK: 数值文本

    /// CPU 榜数值文本：**原值不 clamp**（多线程可 >100%，削平会让排序失真）
    public static func cpuValueText(_ cpuPercent: Double) -> String {
        guard cpuPercent.isFinite else { return "—" }
        return String(format: "%.1f%%", max(0, cpuPercent))
    }

    /// 单条进程在指定维度下的条形比例
    ///
    /// - Parameter memoryTotal: 物理内存总量（内存榜用；nil / 0 时条形为 0）
    public static func barFraction(for usage: ProcessResourceUsage,
                                   metric: SystemProcessMetric,
                                   memoryTotal: UInt64?) -> Double {
        switch metric {
        case .cpu:
            return cpuBarFraction(usage.cpuPercent)
        case .memory:
            return memoryBarFraction(residentBytes: usage.residentBytes,
                                     totalBytes: memoryTotal ?? 0)
        }
    }

    /// 单条进程在指定维度下的数值文本（内存榜带单位；总量不可得也照常显示已用）
    public static func valueText(for usage: ProcessResourceUsage,
                                 metric: SystemProcessMetric) -> String {
        switch metric {
        case .cpu:
            return cpuValueText(usage.cpuPercent)
        case .memory:
            return formatBytes(usage.residentBytes)
        }
    }

    /// 常驻内存文本（1024 进位，B 取整、K 以上 1 位小数）— 与详情页容量口径一致
    public static func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = Double(bytes)
        var index = 0
        while scaled >= 1024, index < units.count - 1 {
            scaled /= 1024
            index += 1
        }
        guard index > 0 else { return String(format: "%.0f %@", scaled, units[index]) }
        return String(format: "%.1f %@", scaled, units[index])
    }
}
