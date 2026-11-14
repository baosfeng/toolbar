import AppKit

// MARK: - 面板设计令牌（五页统一入口）

/// 菜单栏面板样式 — 颜色 / 字体 / 尺寸全部收敛到 `PaneCardStyle`，深浅色自适应
///
/// 收敛理由：网络 / 剪贴板 / 传送此前用 10pt 半粗分区标题、12pt 正文、12pt 等宽数值、
/// 32pt 行高、8pt 圆角与半透明卡片；额度 / Token 用 11pt 粗体标题、10.5pt 数值、9pt 实色卡片。
/// 同一面板切页时两套公式，用户实测反馈「各个 tab 风格不搭」。现在：
/// - 字号与卡片几何只在 `PaneCardStyle` 定义一次，本文件按语义角色转发；
/// - 颜色（下 / 上行、强调、轨道）仍留在本文件，因为网络页的语义色不属于卡片语言。
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

    // MARK: 字体（全部转发 PaneCardStyle，五页同一张字号表）

    /// 分区标题 / 卡片标题（11pt 粗体）
    static let sectionFont: NSFont = PaneCardStyle.sectionTitleFont
    /// 正文 / 行名（10.5pt）
    static let bodyFont: NSFont = PaneCardStyle.rowNameFont
    /// 行数值（10.5pt 等宽）
    static let valueFont: NSFont = PaneCardStyle.rowValueFont
    /// 小号数值（图表坐标 / 表头补充说明，10pt 等宽）
    static let smallValueFont: NSFont = PaneCardStyle.metaFont
    /// 主数值大字号（24pt 等宽粗体，与额度 / Token 页 Hero 同档）
    static let heroFont: NSFont = PaneCardStyle.heroFont
    /// 主数值单位（11pt 半粗）
    static let heroUnitFont: NSFont = PaneCardStyle.heroUnitFont
    /// 次速率数字（网络页上行，14pt 等宽半粗）
    static let sideValueFont: NSFont = PaneCardStyle.sideValueFont

    // MARK: 尺寸（转发 PaneCardStyle）

    /// 普通行高（28pt，五页一致）
    static let rowHeight: CGFloat = PaneCardStyle.rowHeight
    /// 紧凑行高（进程 / 设备行，26pt）
    static let compactRowHeight: CGFloat = PaneCardStyle.compactRowHeight
    /// 卡片圆角（9pt，与额度 / Token / 系统卡片同档）
    static let cornerRadius: CGFloat = PaneCardStyle.cardRadius

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
    ///
    /// 改造后转发主题角色的 `textSecondary`（取值同为 88% labelColor，
    /// 三套主题共用文字通道，换肤不改文字对比度）
    static var secondaryText: NSColor { PaneCardStyle.secondaryText }
    /// 三级文字（9-10pt 图表坐标等）— 62% labelColor
    static var tertiaryText: NSColor { PaneCardStyle.tertiaryText }

    static var downColor: NSColor { .systemGreen }
    static var upColor: NSColor { .systemOrange }
    /// 强调色（转发主题 `accent` 角色 = 系统强调色）
    static var accentColor: NSColor { PaneCardStyle.accentText }
    /// 轨道底色 — **不是** `PaneCardStyle.trackColor`：这一条语义是「在任意底上叠一层
    /// 中性轨道」，走 labelColor 带透明度；主题的 `track` 是有色实值，两者用在不同场景
    static var trackColor: NSColor { dynamicLabel(alpha: 0.14) }
    /// 轻量填充（今日流量卡片 / 悬停行）— 转发主题 `selectedFill`（同为 7% labelColor）
    static var subtleFill: NSColor { PaneCardStyle.selectedFill }
    /// 图表柱（非今天）— 不透明背景上 0.18 偏淡，提到 0.24
    static var barColor: NSColor { dynamicLabel(alpha: 0.24) }
}
