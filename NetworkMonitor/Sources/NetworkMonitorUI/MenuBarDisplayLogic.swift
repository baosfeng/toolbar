import Foundation

// MARK: - 菜单栏显示口径（纯逻辑）

/// 菜单栏显示口径 —— 布局 / 数值单位 / 刷新周期 / 分页重算的判据，与 AppKit 无关
///
/// 取值与 AppKit 侧的 `MenuBarLayout` / `MenuBarUnitStyle` 同名同 rawValue；
/// 本 target 不依赖 Core 与可执行 target（TestRunner 可直接断言），
/// 调用方用 rawValue 字符串对接，两处取值必须一致。
public enum MenuBarDisplayLogic {

    /// 菜单栏布局
    public enum Layout: String, CaseIterable {
        /// 所有指标在同一行（历史形态）
        case singleLine
        /// 上下两行，用换行符分行
        case twoLine
        /// 卡片式：菜单栏高度受限，按两行呈现（与 twoLine 同一实现，不另建形态）
        case card
    }

    /// 数值单位写法
    public enum UnitStyle: String, CaseIterable {
        /// 紧凑写法（"1.2M"，沿用 formatSpeedShort）
        case short
        /// 带空格全称（"1.2 MB/s"）
        case full
        /// 自定义：暂未提供自定义单位表，按 short 回落
        case custom
    }

    /// 设置页可选的刷新周期三档
    public static let refreshIntervalOptions: [TimeInterval] = [1, 2, 5]

    /// 刷新周期上下界（沿用 `MenuBarDisplayPreferences.refreshInterval` 的 1...10 秒）
    public static let refreshIntervalBounds: ClosedRange<TimeInterval> = 1...10

    // MARK: - 偏好 rawValue 对接

    /// 布局 rawValue → 判据实现（非法值回落单行）
    public static func layout(fromRawValue raw: String) -> Layout {
        Layout(rawValue: raw) ?? .singleLine
    }

    /// 单位 rawValue → 判据实现（非法值回落紧凑）
    public static func unitStyle(fromRawValue raw: String) -> UnitStyle {
        UnitStyle(rawValue: raw) ?? .short
    }

    // MARK: - 刷新周期

    /// 夹取后的刷新周期：非有限值 / 非正数回落下界，其余夹到 1...10
    public static func clampedRefreshInterval(_ raw: TimeInterval) -> TimeInterval {
        guard raw.isFinite, raw > 0 else { return refreshIntervalBounds.lowerBound }
        return min(max(raw, refreshIntervalBounds.lowerBound), refreshIntervalBounds.upperBound)
    }

    /// 定时器重建判据：期望周期与正在跑的周期不同才重建（相同则保留运行中的定时器，不重置节拍）
    public static func needsTimerRebuild(currentInterval: TimeInterval, desiredInterval: TimeInterval) -> Bool {
        clampedRefreshInterval(currentInterval) != clampedRefreshInterval(desiredInterval)
    }

    // MARK: - 数值写法

    /// 状态栏速度写法：short 沿用传入的紧凑写法；full 用带空格全称；custom 回落 short
    public static func speedText(shortText: String, unitStyle: UnitStyle) -> String {
        switch unitStyle {
        case .short, .custom: return shortText
        case .full: return fullSpeedText(shortText)
        }
    }

    /// 紧凑写法 → 带空格全称（"1.2M" → "1.2 MB/s"，"0B" → "0 B/s"）
    public static func fullSpeedText(_ shortText: String) -> String {
        guard let unit = shortText.last, let suffix = fullUnitSuffix(for: unit) else {
            return shortText + " B/s"
        }
        return String(shortText.dropLast()) + " " + suffix
    }

    /// 紧凑单位字符 → 全称
    private static func fullUnitSuffix(for unit: Character) -> String? {
        switch unit {
        case "B": return "B/s"
        case "K": return "KB/s"
        case "M": return "MB/s"
        case "G": return "GB/s"
        case "T": return "TB/s"
        default: return nil
        }
    }

    // MARK: - 布局

    /// 是否按两行呈现（card 在菜单栏高度受限时按 twoLine 呈现，同一实现）
    public static func usesTwoLines(_ layout: Layout) -> Bool {
        switch layout {
        case .singleLine: return false
        case .twoLine, .card: return true
        }
    }

    /// 状态栏标题文本：单行按密度分隔符拼接；两行按指标均分上下行（奇数时上行多一段）、用换行符分行
    public static func statusTitle(parts: [String], layout: Layout, separator: String) -> String {
        guard !parts.isEmpty else { return "" }
        guard usesTwoLines(layout), parts.count > 1 else { return parts.joined(separator: separator) }
        let split = (parts.count + 1) / 2
        let top = parts.prefix(split).joined(separator: separator)
        let bottom = parts.dropFirst(split).joined(separator: separator)
        return top + "\n" + bottom
    }

    // MARK: - 分页重算

    /// 可见分页重算后的当前页：仍可见就保留，否则落到第一个可见页（无可见页时保持原值，由调用方兜底）
    public static func resolvedTab(current: Int, visibleTabs: [Int]) -> Int {
        if visibleTabs.contains(current) { return current }
        return visibleTabs.first ?? current
    }
}
