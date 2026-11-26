import Foundation
import NetworkMonitorCore

// MARK: - 菜单栏标签档

/// 菜单栏标签（指标前缀）档 —— 纯逻辑，与 AppKit 无关
///
/// 用户口述「菜单栏直接展示 Token 等很大的标识，太浪费空间」，所以这里只解决
/// 「前缀多长」这一件事：`full` = 接入本偏好之前的逐字前缀，`short` = 1–2 字符。
///
/// 为什么没有第三档「只显示 SF Symbol」：`NSStatusBarButton` 只有一枚 `image`
/// 加一段 `attributedTitle`，而状态栏是按指标片段拼出来的一整行（`↓1.2M  C 40%`），
/// 让 17 项各出一枚图标只能自绘整条状态栏图；那条路还要与 ⚠️ 告警前缀、⏸ 暂停前缀
/// 逐片段重新排版。ivu 项目「不留死开关」的纪律，这里只给能真生效的两档。
public enum MenuBarLabelStyle: String, CaseIterable, Sendable {

    /// 完整标签（默认档，等于改造前的硬编码前缀）
    case full
    /// 短标签（1–2 字符）
    case short

    /// 设置页分段标题
    public var title: String {
        switch self {
        case .full: return "完整"
        case .short: return "短标签"
        }
    }

    /// 设置页副标题：写出当前档的真实渲染示例，避免「选了看不出变化」
    public var detailText: String {
        let prefix = MenuBarLabelResolver.primaryLabel(for: .tokenToday, style: self, customLabels: [:])
        let cpu = MenuBarLabelResolver.primaryLabel(for: .cpu, style: self, customLabels: [:])
        return "当前写法：\(prefix)2.51亿  \(cpu)40%"
    }
}

// MARK: - 标签解析

/// 标签解析 —— 三档优先级：**逐项自定义 > 档位（short / full）> 内置默认**
///
/// 自定义值只做两件事：去掉首尾空白、空值视为「没填」。
/// 补尾随空格的责任在这里，不在渲染处：`↓` / `↑` 与数值之间历史上就没有空格，
/// 而自定义文本（`T`、`Token`）必须有空格才不与数值粘在一起。
public enum MenuBarLabelResolver {

    /// 磁盘 I/O 的第二个片段（写）的自定义键
    ///
    /// 与 `diskIO` 分开存：读 `R` 与写 `W` 是两个片段，共用一个自定义值会让
    /// 两段渲染成一模一样的文本，菜单栏上分不出读还是写。
    public static let diskWriteKey = "diskIO.write"

    /// 主片段标签
    /// - Parameters:
    ///   - customLabels: 偏好键 `menuBar.customLabels`（metric rawValue → 自定义文本）
    public static func primaryLabel(for metric: MenuBarMetric,
                                    style: MenuBarLabelStyle,
                                    customLabels: [String: String]) -> String {
        let fallback = style == .full ? metric.fullLabel : metric.shortLabel
        return resolved(custom: customLabels[metric.rawValue], fallback: fallback,
                        addsSpace: !isArrowGlyph(metric))
    }

    /// 第二片段标签（只有磁盘 I/O 有；其余返回 nil）
    public static func secondaryLabel(for metric: MenuBarMetric,
                                      style: MenuBarLabelStyle,
                                      customLabels: [String: String]) -> String? {
        guard let full = metric.secondaryFullLabel else { return nil }
        let fallback = style == .full ? full : (metric.secondaryShortLabel ?? full)
        let key = metric == .diskIO ? diskWriteKey : metric.rawValue
        return resolved(custom: customLabels[key], fallback: fallback, addsSpace: true)
    }

    /// 某一项的「渲染成什么」示例 —— 设置页逐项自定义弹窗的占位提示用
    public static func placeholder(for metric: MenuBarMetric, style: MenuBarLabelStyle) -> String {
        let full = metric.fullLabel.trimmingCharacters(in: .whitespaces)
        let short = metric.shortLabel.trimmingCharacters(in: .whitespaces)
        return "默认 \(full) / 短标签 \(short)"
    }

    // MARK: - 内部

    /// ↓ / ↑ 是符号不是文字，历史上直接与数值相连（`↓1.2M`）
    private static func isArrowGlyph(_ metric: MenuBarMetric) -> Bool {
        metric == .upSpeed || metric == .downSpeed
    }

    private static func resolved(custom: String?, fallback: String, addsSpace: Bool) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return fallback }
        guard addsSpace, trimmed.last?.isWhitespace != true else { return trimmed }
        return trimmed + " "
    }
}
