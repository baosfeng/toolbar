import AppKit

// MARK: - 面板设计令牌（拆出自 MenuPanelComponents.swift，原文件超单文件 15 KiB 上限）

/// 菜单栏面板样式 — 颜色/字体/尺寸全部走系统语义 API（深浅色自适应）
///
/// 尺寸以 4pt 为基准；数字一律 `monospacedDigit`，避免每秒刷新时宽度抖动。
@MainActor
enum MenuPanelStyle {
    /// 面板宽度（设计稿 320）
    static let panelWidth: CGFloat = 320
    /// 内容左右留白
    static let inset: CGFloat = 12
    /// 面板最大高度 — 超出后由内部 NSScrollView 垂直滚动（不裁切内容）
    static let maxHeight: CGFloat = 520
    /// 内容可用宽度
    static var contentWidth: CGFloat { panelWidth - inset * 2 }

    // MARK: 字体

    /// 分区标题
    static let sectionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 正文
    static let bodyFont = NSFont.systemFont(ofSize: 12)
    /// 数值（等宽数字）
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    /// 小号数值（进程行 / 图表数值）
    static let smallValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 主速率大数字
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
    /// 主速率单位
    static let heroUnitFont = NSFont.systemFont(ofSize: 11)
    /// 次速率数字
    static let sideValueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)

    // MARK: 尺寸

    /// 普通行高
    static let rowHeight: CGFloat = 32
    /// 紧凑行高（进程行）
    static let compactRowHeight: CGFloat = 28
    /// 圆角
    static let cornerRadius: CGFloat = 8

    // MARK: 颜色

    /// 动态半透明前景色 — 随外观变化重新解析
    ///
    /// 不能直接用 `NSColor.labelColor.withAlphaComponent(...)`：该调用会在创建瞬间
    /// 按当前外观解析并固化颜色，强制外观渲染（快照取证）或运行期切换深浅色时，
    /// 旧颜色会残留在新外观上（浅色下文字发白）。dynamicProvider 每次解析都重新取基准色。
    static func dynamicLabel(alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let base: NSColor = isDark ? .white : .black
            return base.withAlphaComponent(alpha)
        }
    }

    /// 次要文字 — 替代 secondaryLabelColor：后者在小字号（10-12pt）+
    /// windowBackgroundColor 上实测只有 ~3.9:1，达不到 4.5:1，故用 88% labelColor
    static var secondaryText: NSColor { dynamicLabel(alpha: 0.88) }
    /// 三级文字（9pt 图表坐标等）— 62% labelColor
    static var tertiaryText: NSColor { dynamicLabel(alpha: 0.62) }

    static var downColor: NSColor { .systemGreen }
    static var upColor: NSColor { .systemOrange }
    static var accentColor: NSColor { .controlAccentColor }
    /// 轨道底色（labelColor 带透明度，深浅色自适应）
    static var trackColor: NSColor { dynamicLabel(alpha: 0.14) }
    /// 轻量填充（今日流量卡片 / 悬停行）
    static var subtleFill: NSColor { dynamicLabel(alpha: 0.07) }
    /// 图表柱（非今天）— 不透明背景上 0.18 偏淡，提到 0.24
    static var barColor: NSColor { dynamicLabel(alpha: 0.24) }
}
