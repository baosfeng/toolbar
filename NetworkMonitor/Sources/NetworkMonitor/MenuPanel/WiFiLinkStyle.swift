import AppKit
import NetworkMonitorCore

// MARK: - Wi-Fi 链路样式（网络页链路条与系统页状态带共用）

/// Wi-Fi 链路的派生样式 — 与 `SystemPaneStyle` 同一口径：只用项目既有语义色
///
/// **禁止新造紫 / 青、禁止 color-mix 式混色**：v3 原型用 success + accent 40% 在 oklab 里
/// 插值，实测 hue 落到 178°（青）被打回。这里四个档位直接取 `.systemGreen` / `.systemBlue` /
/// `.systemYellow` / `.systemRed` 原色，不做任何插值。
///
/// 圆点是**非文本图形**（7pt 实心块），按 WCAG 1.4.11 只需 3:1——四色在浅色白底上实测仅
/// green 2.02:1 / yellow 1.41:1 / blue 3.70:1 / red 3.43:1，绿与黄不足 3:1。
/// 因此圆点额外描一圈 `trackColor` 内边（见 `WiFiSignalDotView.draw`），用「色块 + 边框」
/// 保证可辨，而不是把颜色调深——调深就是往 fg 混色，正是被打回的那种做法。
@MainActor
enum WiFiLinkStyle {

    /// 链路条 / 状态带高度（与系统页状态带同一规格）
    static let barHeight: CGFloat = 20

    /// 数值字体（等宽数字，避免 −65 / −100 位宽跳变）
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    /// 档位圆点直径
    static let dotDiameter: CGFloat = 7

    /// 档位 → 圆点颜色
    ///
    /// 未知（含「Wi-Fi 不可得」）给轨道灰：表达「不可判定」，而不是用红色冒充「很差」。
    static func dotColor(for quality: WiFiSignalQuality) -> NSColor {
        switch quality {
        case .excellent, .good: return .systemGreen
        case .fair: return .systemBlue
        case .weak: return .systemYellow
        case .poor: return .systemRed
        case .unknown: return MenuPanelStyle.trackColor
        }
    }
}
