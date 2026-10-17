import Foundation

// MARK: - 菜单面板指标（纯逻辑）

/// 菜单面板展示用的纯计算 — 不依赖 AppKit，供菜单栏面板与 TestRunner 共用
///
/// 面板的取数口径（近 6 日柱状图、今日流量占比、柱高比例、速率拆分、进程 Top N）
/// 全部收敛在这里，避免 UI 里再写一份判断而与测试脱节。
public enum MenuPanelMetrics {

    /// 单日流量柱状图数据项
    public struct DailyTrafficBar: Equatable, Sendable {
        /// 日期短标签（如 "10/16"）
        public let label: String
        /// 下行字节数
        public let rx: UInt64
        /// 上行字节数
        public let tx: UInt64
        /// 是否为今天（UI 用强调色高亮）
        public let isToday: Bool

        public init(label: String, rx: UInt64, tx: UInt64, isToday: Bool) {
            self.label = label
            self.rx = rx
            self.tx = tx
            self.isToday = isToday
        }
    }

    /// 取近 N 日柱状图数据
    ///
    /// 入参约定为「今天在最前」的降序列表（`TrafficTrackingService.weekEntries` 即此顺序），
    /// 返回值改成时间正序：最左最早，最右今天，直接对应柱状图从左到右的画法。
    /// - Parameters:
    ///   - entries: 日期降序的每日流量
    ///   - limit: 最多保留几天；≤ 0 返回空数组
    public static func recentDays(entries: [(label: String, rx: UInt64, tx: UInt64)],
                                 limit: Int) -> [DailyTrafficBar] {
        guard limit > 0 else { return [] }
        return entries.prefix(limit).enumerated().map { index, entry in
            DailyTrafficBar(label: entry.label, rx: entry.rx, tx: entry.tx, isToday: index == 0)
        }.reversed()
    }

    /// 下行占今日总量（下行 + 上行）的比例；总量为 0 时返回 0（不产生无意义的百分比）
    public static func downShare(rx: UInt64, tx: UInt64) -> Double {
        let total = rx + tx
        guard total > 0 else { return 0 }
        return Double(rx) / Double(total)
    }

    /// 柱高比例（相对最大值，0...1）；最大值为 0 时全部为 0
    public static func barRatios(values: [UInt64]) -> [Double] {
        guard let maxValue = values.max(), maxValue > 0 else {
            return values.map { _ in 0 }
        }
        return values.map { Double($0) / Double(maxValue) }
    }

    /// 速率拆成「数值 + 单位」两段（面板大数字与单位分别排版）
    ///
    /// 例：1_200_000 → ("1.2", "MB/s")；负数按绝对值处理；0 → ("0", "B/s")
    public static func speedParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let bps = abs(bytesPerSecond)
        switch bps {
        case 1_000_000_000...:
            return (String(format: "%.1f", bps / 1_000_000_000), "GB/s")
        case 1_000_000...:
            return (String(format: "%.1f", bps / 1_000_000), "MB/s")
        case 1_000...:
            return (String(format: "%.0f", bps / 1_000), "KB/s")
        default:
            return (String(format: "%.0f", bps), "B/s")
        }
    }

    /// 活跃进程 Top N：过滤零流量后按总量降序（面板与菜单共用同一口径）
    public static func topProcesses(_ processes: [ProcessNetUsage], limit: Int) -> [ProcessNetUsage] {
        guard limit > 0 else { return [] }
        return processes
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }
}
