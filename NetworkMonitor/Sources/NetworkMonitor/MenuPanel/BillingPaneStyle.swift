import AppKit

// MARK: - 额度页样式（对 PaneCardStyle 的转发）

/// 额度页字体 / 颜色 —— **全部转发到 `PaneCardStyle`**
///
/// 两页共用一套卡片语言后，本文件不再定义原始取值；保留同名成员让
/// `BillingPane*.swift` / `BillingProviderBlockView.swift` 的调用点零改动。
/// 死令牌（原 `heroFont` 25pt / `accentTile`）已随收敛删除。
@MainActor
enum BillingPaneStyle {

    // MARK: 字体

    /// provider 名称（卡头主标题，11pt 粗体）
    static let providerFont: NSFont = PaneCardStyle.cardTitleFont
    /// 卡片小标题 / 分区标题（11pt 粗体）
    static let cardTitleFont: NSFont = PaneCardStyle.cardTitleFont
    /// 正文（10.5pt）
    static let labelFont: NSFont = PaneCardStyle.rowNameFont
    /// 金额 / 数值（10.5pt 等宽）
    static let monoFont: NSFont = PaneCardStyle.rowValueFont
    /// 指标数值（10.5pt 等宽粗体）
    static let metricValueFont: NSFont = PaneCardStyle.rowValueStrongFont
    /// 聚合块：额度百分比（19pt 等宽粗体 —— 与 Token 卡值同档）
    static let cellValueFont: NSFont = PaneCardStyle.cardValueFont
    /// 聚合块：百分比单位（9.5pt 等宽半粗）
    static let cellValueUnitFont: NSFont = PaneCardStyle.cardValueUnitFont
    /// 聚合块：额度名称（10.5pt）
    static let cellTitleFont: NSFont = PaneCardStyle.rowNameFont
    /// 聚合块：重置时间（8.5pt 等宽）
    static let resetFont: NSFont = PaneCardStyle.axisFont
    /// 聚合块：provider 名称（11pt 粗体）
    static let blockNameFont: NSFont = PaneCardStyle.cardTitleFont
    /// 说明与时间戳（10pt）
    static let subFont: NSFont = PaneCardStyle.metaFont
    /// 页头时间戳（10pt 等宽）
    static let stampFont: NSFont = PaneCardStyle.metaFont
    /// 范围按钮（10.5pt 半粗 / 选中粗体）
    static let rangeFont: NSFont = PaneCardStyle.segmentFont
    static let rangeSelectedFont: NSFont = PaneCardStyle.segmentSelectedFont
    /// 图表坐标轴（8.5pt 等宽）
    static let axisFont: NSFont = PaneCardStyle.axisFont
    /// 模型名（10.5pt 等宽）
    static let modelNameFont: NSFont = PaneCardStyle.modelNameFont
    /// 模型金额（10.5pt 等宽粗体）
    static let modelAmountFont: NSFont = PaneCardStyle.rowValueStrongFont
    /// 模型请求数（10pt 等宽）
    static let modelRequestFont: NSFont = PaneCardStyle.metaFont
    /// 说明段落（10pt）
    static let noteFont: NSFont = PaneCardStyle.metaFont
    /// 状态胶囊（9.5pt 半粗）
    static let chipFont: NSFont = PaneCardStyle.chipFont

    // MARK: 颜色

    /// 卡片底（实色面 —— 与 Token 页同一取值）
    static var cardFill: NSColor { PaneCardStyle.cardFill }
    /// 状态带底
    static var bandFill: NSColor { PaneCardStyle.bandFill }
    /// 强调色浅底（分段选中态 15%）
    static var accentSoft: NSColor { PaneCardStyle.accentSoft }
    /// 危险色浅底（错误条 10%）
    static var dangerSoft: NSColor { PaneCardStyle.dangerSoft }
    /// 1pt 浅分隔线
    static var hairline: NSColor { PaneCardStyle.hairline }
    /// 轨道底
    static var trackColor: NSColor { PaneCardStyle.trackColor }
    /// 输入框边框
    static var fieldBorder: NSColor { PaneCardStyle.fieldBorder }
    /// 告警墨色 / 正常墨色（进度条分级与胶囊用同一套墨色）
    static var warnInk: NSColor { PaneCardStyle.warnInk }
    static var okInk: NSColor { PaneCardStyle.okInk }

    // MARK: 动态文字色

    /// 次要文字色
    static var secondaryText: NSColor { PaneCardStyle.secondaryText }
    /// 三级文字色
    static var tertiaryText: NSColor { PaneCardStyle.tertiaryText }

    // MARK: 尺寸

    static let cardRadius: CGFloat = PaneCardStyle.cardRadius
    static let cardPaddingX: CGFloat = PaneCardStyle.cardPaddingX
    static let cardPaddingY: CGFloat = PaneCardStyle.cardPaddingY
    static let cardSpacing: CGFloat = PaneCardStyle.cardSpacing
    static let heroHeight: CGFloat = PaneCardStyle.heroHeight
    static let pageHeadHeight: CGFloat = PaneCardStyle.pageHeadHeight
    static let stateBandHeight: CGFloat = PaneCardStyle.stateBandHeight
    static let sparkHeight: CGFloat = PaneCardStyle.sparkHeight
}
