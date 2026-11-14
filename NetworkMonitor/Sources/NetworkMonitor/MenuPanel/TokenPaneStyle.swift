import AppKit

// MARK: - Token 页样式（对 PaneCardStyle 的转发）

/// Token 页字体 / 颜色 / 尺寸 —— **全部转发到 `PaneCardStyle`**
///
/// 两页共用一套卡片语言后，本文件不再定义任何原始取值（颜色与字号只在
/// `PaneCardStyle` 出现一次）。保留同名成员是为了让 `TokenPane*.swift` 的
/// 调用点零改动；新增取值请先加到 `PaneCardStyle`，这里只做转发。
@MainActor
enum TokenPaneStyle {

    // MARK: 字体

    static let pageHeadFont: NSFont = PaneCardStyle.cardTitleFont
    static let cardValueFont: NSFont = PaneCardStyle.cardValueFont
    static let cardValueUnitFont: NSFont = PaneCardStyle.cardValueUnitFont
    static let cardTitleFont: NSFont = PaneCardStyle.cardTitleFont
    static let cardHeadTitleFont: NSFont = PaneCardStyle.cardTitleFont
    static let heroFont: NSFont = PaneCardStyle.heroFont
    static let heroUnitFont: NSFont = PaneCardStyle.heroUnitFont
    static let metaFont: NSFont = PaneCardStyle.metaFont
    static let metaNumberFont: NSFont = PaneCardStyle.metaFont
    static let metaValueFont: NSFont = PaneCardStyle.cardValueUnitFont
    static let axisFont: NSFont = PaneCardStyle.axisFont
    static let legendFont: NSFont = PaneCardStyle.legendFont
    static let legendValueFont: NSFont = PaneCardStyle.legendValueFont
    static let cardFooterFont: NSFont = PaneCardStyle.metaFont
    static let yoyFont: NSFont = PaneCardStyle.rowValueStrongFont
    static let textButtonFont: NSFont = PaneCardStyle.chipFont
    static let segmentFont: NSFont = PaneCardStyle.segmentFont
    static let segmentSelectedFont: NSFont = PaneCardStyle.segmentSelectedFont
    static let rowNameFont: NSFont = PaneCardStyle.rowNameFont
    static let rowValueFont: NSFont = PaneCardStyle.rowValueFont
    static let rowPercentFont: NSFont = PaneCardStyle.metaFont
    static let keyRowTitleFont: NSFont = PaneCardStyle.rowNameFont
    static let keyRowValueFont: NSFont = PaneCardStyle.rowValueStrongFont
    static let noteFont: NSFont = PaneCardStyle.metaFont
    static let ringTextFont: NSFont = PaneCardStyle.rowValueStrongFont
    static let stateFont: NSFont = PaneCardStyle.legendFont
    static let stateValueFont: NSFont = PaneCardStyle.rowValueStrongFont
    static let heroLabelFont: NSFont = PaneCardStyle.cardTitleFont
    static let heroMainFont: NSFont = PaneCardStyle.heroFont
    static let heroMainUnitFont: NSFont = PaneCardStyle.heroUnitFont
    static let heroDeltaFont: NSFont = PaneCardStyle.heroUnitFont
    static let heroClockFont: NSFont = PaneCardStyle.metaFont
    /// 兼容旧成员（状态页 / 分段控件仍引用）
    static let miniValueFont: NSFont = PaneCardStyle.rowValueStrongFont
    static let stateBodyFont: NSFont = PaneCardStyle.bodyFont
    static let stateNoteFont: NSFont = PaneCardStyle.metaFont

    // MARK: 颜色（四族 / 轨道 / 文本）

    static var uncachedColor: NSColor { PaneCardStyle.uncachedColor }
    static var uncachedInk: NSColor { PaneCardStyle.uncachedInk }
    static var cacheColor: NSColor { PaneCardStyle.cacheColor }
    static var cacheInk: NSColor { PaneCardStyle.cacheInk }
    static var outputColor: NSColor { PaneCardStyle.outputColor }
    static var outputInk: NSColor { PaneCardStyle.outputInk }
    static var requestColor: NSColor { PaneCardStyle.requestColor }
    static var requestInk: NSColor { PaneCardStyle.requestInk }
    static var inputColor: NSColor { PaneCardStyle.uncachedColor }
    static var ghostColor: NSColor { PaneCardStyle.ghostColor }
    static var cardFill: NSColor { PaneCardStyle.cardFill }
    static var bandFill: NSColor { PaneCardStyle.bandFill }
    static var trackColor: NSColor { PaneCardStyle.trackColor }
    static var trackStrong: NSColor { PaneCardStyle.trackStrong }
    static var rowAltFill: NSColor { PaneCardStyle.bandFill }
    static var hairline: NSColor { PaneCardStyle.hairline }
    static var gridLine: NSColor { PaneCardStyle.gridLine }
    static var uncachedCardFill: NSColor { PaneCardStyle.uncachedCardFill }
    static var cacheCardFill: NSColor { PaneCardStyle.cacheCardFill }
    static var outputCardFill: NSColor { PaneCardStyle.outputCardFill }
    static var requestCardFill: NSColor { PaneCardStyle.requestCardFill }
    static var cacheStackFill: NSColor { PaneCardStyle.cacheStackFill }
    static var warnInk: NSColor { PaneCardStyle.warnInk }
    static var okInk: NSColor { PaneCardStyle.okInk }
    static var okColor: NSColor { PaneCardStyle.okColor }
    static var secondaryText: NSColor { PaneCardStyle.secondaryText }
    static var tertiaryText: NSColor { PaneCardStyle.tertiaryText }
    static var selectedFill: NSColor { PaneCardStyle.selectedFill }
    static var currentHourWash: NSColor { PaneCardStyle.accentWash }
    static var accentText: NSColor { PaneCardStyle.accentText }

    // MARK: 尺寸

    static let cardInset: CGFloat = PaneCardStyle.cardInset
    static let cardRadius: CGFloat = PaneCardStyle.cardRadius
    static let cardPaddingX: CGFloat = PaneCardStyle.cardPaddingX
    static let cardPaddingY: CGFloat = PaneCardStyle.cardPaddingY
    static let detailChartHeight: CGFloat = 70
    static let sparkHeight: CGFloat = PaneCardStyle.sparkHeight
    /// 卡内迷你折线宽度 —— 随渲染档（省电档收窄到 40pt，减少同一行的重绘面积）
    static var cardSparkWidth: CGFloat { CGFloat(ThemeStyle.profile.sparkWidth) }
    static let stateBandHeight: CGFloat = PaneCardStyle.stateBandHeight
    static let ringSize: CGFloat = PaneCardStyle.ringSize
    static let ringWidth: CGFloat = PaneCardStyle.ringWidth
    static let bigRingSize: CGFloat = PaneCardStyle.bigRingSize
    static let bigRingWidth: CGFloat = PaneCardStyle.bigRingWidth
    static let usageChartHeight: CGFloat = PaneCardStyle.usageChartHeight
    static let usageTrendHeight: CGFloat = PaneCardStyle.usageTrendHeight
    static let stackBarHeight: CGFloat = 7
    static let pairLineInset: CGFloat = 1.8
    static let heroHeight: CGFloat = PaneCardStyle.heroHeight
    static let familyCardHeight: CGFloat = 59
    static let distroRowHeight: CGFloat = 26
    static let distroDetailRowHeight: CGFloat = 16
    static let distroValueWidth: CGFloat = 44
    static let hourChartHeight: CGFloat = 92
    static let trendChartHeight: CGFloat = 100
    static let miniChartHeight: CGFloat = 30
    static let miniHeight: CGFloat = 46
    static let donutSize: CGFloat = 86
    static let donutRingWidth: CGFloat = 10

    // MARK: 工具

    /// 分族卡配色（0 未缓存 / 1 输出 / 2 缓存读 / 3 请求数）
    static func metricColor(_ index: Int) -> NSColor {
        switch index {
        case 0: return PaneCardStyle.uncachedColor
        case 1: return PaneCardStyle.outputColor
        case 2: return PaneCardStyle.cacheColor
        default: return PaneCardStyle.requestColor
        }
    }

    static func metricInk(_ index: Int) -> NSColor {
        switch index {
        case 0: return PaneCardStyle.uncachedInk
        case 1: return PaneCardStyle.outputInk
        case 2: return PaneCardStyle.cacheInk
        default: return PaneCardStyle.requestInk
        }
    }

    static func metricCardFill(_ index: Int) -> NSColor {
        switch index {
        case 0: return PaneCardStyle.uncachedCardFill
        case 1: return PaneCardStyle.outputCardFill
        case 2: return PaneCardStyle.cacheCardFill
        default: return PaneCardStyle.requestCardFill
        }
    }

    /// 分布条配色：按序号轮转（项目 / 模型共用同一取色函数）
    static func distroColor(_ index: Int) -> NSColor {
        switch index % 6 {
        case 0: return PaneCardStyle.uncachedColor
        case 1: return PaneCardStyle.cacheColor
        case 2: return PaneCardStyle.outputColor
        case 3: return PaneCardStyle.requestColor
        case 4: return PaneCardStyle.ghostColor
        default: return PaneCardStyle.trackStrong
        }
    }

    static func modelColor(_ index: Int) -> NSColor { distroColor(index) }
}
