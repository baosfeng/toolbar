import Foundation

// MARK: - Token 用量展示口径（纯函数）

/// Token 数值 / 日期 / 环比的展示口径
///
/// 放在 Core 而不是 UI 层：TestRunner 只依赖 `NetworkMonitorCore`，口径必须可被断言。
/// Token 页与数据层共用同一套缩写与日期窗口算法，避免 UI 各处重复实现。
public enum TokenFormat {

    /// 缩写数值：`1.2K` / `399.2M` / `10.1B`
    ///
    /// 口径与定稿原型一致：≥10 的 M/B 值保留 1 位小数（B 恒 2 位），其余保留 2 位，
    /// 末尾多余的 0 与小数点去掉（100.0M → 100M）。
    public static func abbreviated(_ value: Int) -> String {
        if value < 0 { return String(value) }
        if value >= 1_000_000_000 {
            return trimmed(Double(value) / 1_000_000_000, decimals: 2) + "B"
        }
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return trimmed(millions, decimals: millions >= 10 ? 1 : 2) + "M"
        }
        if value >= 1_000 {
            return trimmed(Double(value) / 1_000, decimals: 1) + "K"
        }
        return String(value)
    }

    /// 千分位分组：`72,271`
    public static func grouped(_ value: Int) -> String {
        let negative = value < 0
        let digits = Array(String(value.magnitude))
        var output: [Character] = []
        for (index, digit) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { output.append(",") }
            output.append(digit)
        }
        return (negative ? "-" : "") + String(output.reversed())
    }

    /// 百分比：`98.6%`；无数据（nil）显示破折号，不显示 0%
    public static func percent(_ fraction: Double?, decimals: Int = 1) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return String(format: "%.\(decimals)f%%", fraction * 100)
    }

    /// 日期键的月-日：`2026-10-24` → `10-24`
    public static func mmdd(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3 else { return dayKey }
        return parts[1] + "-" + parts[2]
    }

    /// 日期键加减天数（跨月 / 跨年由日历处理，非法输入原样返回）
    public static func dayKey(offsetDays delta: Int, from dayKey: String) -> String {
        guard let date = dayDate(dayKey),
              let shifted = calendar().date(byAdding: .day, value: delta, to: date)
        else { return dayKey }
        return dayString(shifted)
    }

    /// 以 `lastDay` 结尾的连续 `days` 个日期键（升序）
    ///
    /// 例：`dayKeys(lastDay: "2026-10-24", days: 7)` → 10-18 … 10-24。
    public static func dayKeys(lastDay: String, days: Int) -> [String] {
        guard days > 0 else { return [] }
        return (0..<days).map { dayKey(offsetDays: -(days - 1 - $0), from: lastDay) }
    }

    // MARK: - 内部

    /// 去除小数末尾的 0 与孤立小数点
    private static func trimmed(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 固定 UTC 日历 —— 只做日期键平移，不含时区语义，避免夏令时影响天数
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func dayDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar().date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dayString(_ date: Date) -> String {
        let components = calendar().dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

// MARK: - 环比与同期汇总

/// 环比与「今日截至当前小时」的汇总口径
public enum TokenComparison {

    /// 单指标环比结果
    public struct Delta: Sendable, Equatable {
        /// 涨跌方向
        public enum Direction: Sendable, Equatable {
            case up
            case down
        }

        /// 展示文案，如 `↑ 35%` / `↑ 12.4×` / `↓ 8%`
        public let text: String
        /// 涨跌方向
        public let direction: Direction

        public init(text: String, direction: Direction) {
            self.text = text
            self.direction = direction
        }
    }

    /// 环比：今日 vs 昨日同期
    ///
    /// - 昨日为 0（含无数据）时返回 nil —— 不展示 `↑ ∞` 这类无意义徽标；
    /// - 比值 ≥10 用倍数表达，1…10 用百分比上涨，<1 用百分比下跌。
    public static func delta(today: Int, yesterday: Int) -> Delta? {
        guard yesterday > 0 else { return nil }
        let ratio = Double(today) / Double(yesterday)
        if ratio >= 10 {
            return Delta(text: "↑ " + String(format: "%.1f", ratio) + "×", direction: .up)
        }
        if ratio >= 1 {
            return Delta(text: "↑ \(Int(((ratio - 1) * 100).rounded()))%", direction: .up)
        }
        return Delta(text: "↓ \(Int(((1 - ratio) * 100).rounded()))%", direction: .down)
    }

    /// 汇总 0…`throughHour`（含）的小时用量；`usage == nil` 的缺省槽位按 0 处理
    public static func sum(hourly: [HarnessHourlyUsage], throughHour: Int) -> HarnessTokenUsage {
        guard throughHour >= 0 else { return .zero }
        return hourly.reduce(HarnessTokenUsage.zero) { partial, slot in
            guard slot.hour <= throughHour, let usage = slot.usage else { return partial }
            return partial.adding(usage)
        }
    }

    /// 汇总整日小时用量（不设上限）
    public static func sum(hourly: [HarnessHourlyUsage]) -> HarnessTokenUsage {
        sum(hourly: hourly, throughHour: 23)
    }

    /// 快照是否完全没有可展示的数据（空态判据）
    public static func isEmpty(_ snapshot: HarnessUsageSnapshot) -> Bool {
        snapshot.totals.allTime.isZero
            && snapshot.daily.isEmpty
            && snapshot.models.isEmpty
            && snapshot.projects.isEmpty
    }
}
