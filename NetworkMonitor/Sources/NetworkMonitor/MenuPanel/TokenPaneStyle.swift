import AppKit

// MARK: - Token 页样式令牌

/// Token 页字体 / 颜色 / 尺寸 —— 对齐定稿原型 .open-design/token-redesign/final-定稿.html
///
/// 四个指标族各有「主色 / 文字级主色 / 卡片底 / 填充」四档，深浅色只在 dynamic(:) 里各写一次原始值；
/// 所有视图取色都走这里，不散落裸色值。
@MainActor
enum TokenPaneStyle {

    // MARK: 字体（r3 起按可读性下限整体上调：主数值 ≥18 / 卡标题 ≥11 / 辅助行与图例 ≥10）

    static let pageTitleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    /// 页头主机名（11pt 半粗）
    static let pageHeadFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// 四族卡主数值（19pt 等宽粗体，比 hero 低一档）
    static let cardValueFont = NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .bold)
    /// 卡片标题（11pt 粗体）
    static let cardTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// 二级页大数字（26pt 等宽粗体）
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)
    /// 二级页大数字单位（11pt 等宽）
    static let heroUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let sectionTitleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    /// 卡头标题（11pt 粗体）
    static let cardHeadTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// 补充说明（10pt）
    static let metaFont = NSFont.systemFont(ofSize: 10)
    /// 卡头补充说明（10pt 等宽数字）
    static let metaNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 卡头说明里的数值（10.5pt 等宽半粗）
    static let metaValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    /// 坐标轴（8.5pt 等宽）
    static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
    /// 图例（10pt 半粗）
    static let legendFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 图例数值（10pt 等宽半粗）
    static let legendValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 卡片辅助行（10pt 等宽数字）
    static let cardFooterFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 同比数值（10.5pt 等宽粗体）
    static let yoyFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
    /// 行内文字按钮（「切：请求数」「切：分线」，10pt 粗体）
    static let textButtonFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    /// 分段按钮（10.5pt 半粗）
    static let segmentFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    /// 分段按钮选中态（10.5pt 粗体）
    static let segmentSelectedFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)
    /// 迷你分段（10pt 半粗）
    static let miniSegmentFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 行名（10.5pt）
    static let rowNameFont = NSFont.systemFont(ofSize: 10.5)
    /// 行数值（10.5pt 等宽）
    static let rowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// 行占比（10pt 等宽）
    static let rowPercentFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 二级页键值行标题（10.5pt 半粗）
    static let keyRowTitleFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    /// 二级页键值行数值（11.5pt 等宽半粗）
    static let keyRowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    /// 二级页口径说明（10pt）
    static let noteFont = NSFont.systemFont(ofSize: 10)
    /// 环形图中心数字（10.5pt 等宽粗体）
    static let ringTextFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
    /// 状态带（10pt 半粗）
    static let stateFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 状态带数值（10.5pt 等宽半粗）
    static let stateValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

    // MARK: 首屏 Hero 字体（今日总消耗 = 全界面最大字号）

    /// Hero 标题（11pt 半粗）
    static let heroLabelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// Hero 主数值（24pt 等宽粗体）
    static let heroMainFont = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
    /// Hero 单位（11pt 等宽半粗）
    static let heroMainUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// Hero 同比（11pt 等宽半粗）
    static let heroDeltaFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// Hero 实时时间（10pt 等宽）
    static let heroClockFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    // MARK: 兼容旧成员（状态页 / 分段控件仍引用）

    static let chipTitleFont = NSFont.systemFont(ofSize: 10)
    static let chipValueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    static let chipShareFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    static let badgeTitleFont = NSFont.systemFont(ofSize: 10)
    static let badgeValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let miniTitleFont = NSFont.systemFont(ofSize: 10)
    static let miniValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let listNameFont = NSFont.systemFont(ofSize: 11)
    static let listSubFont = NSFont.systemFont(ofSize: 10)
    static let listValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    static let footerFont = NSFont.systemFont(ofSize: 10)
    static let stateBodyFont = NSFont.systemFont(ofSize: 12)
    static let stateNoteFont = NSFont.systemFont(ofSize: 10)
    /// 未缓存输入
    static var uncachedColor: NSColor { dynamic(light: 0x0071E3, dark: 0x409CFF) }
    static var uncachedInk: NSColor { dynamic(light: 0x0058B3, dark: 0x6FB6FF) }
    /// 缓存读
    static var cacheColor: NSColor { dynamic(light: 0x0D9488, dark: 0x2DD4BF) }
    static var cacheInk: NSColor { dynamic(light: 0x0B6D64, dark: 0x5CE3D2) }
    /// 输出
    static var outputColor: NSColor { dynamic(light: 0x5B5BD6, dark: 0xA89DFF) }
    static var outputInk: NSColor { dynamic(light: 0x4A44B8, dark: 0xBFB6FF) }
    /// 请求数
    static var requestColor: NSColor { dynamic(light: 0xC2410C, dark: 0xFF8A4C) }
    static var requestInk: NSColor { dynamic(light: 0xA83A0B, dark: 0xFFAB7D) }
    /// 输入（旧成员名，等价未缓存）
    static var inputColor: NSColor { uncachedColor }
    /// 昨日 / 上一周期对照
    static var ghostColor: NSColor { dynamic(light: 0xB4B4BE, dark: 0x6A6A72) }

    // MARK: 卡片底与轨道

    static var cardFill: NSColor { dynamic(light: 0xF5F5F7, dark: 0x26262A) }
    static var bandFill: NSColor { dynamic(light: 0xEEEFF2, dark: 0x2B2B30) }
    static var trackColor: NSColor { dynamic(light: 0xE4E4EA, dark: 0x39393F) }
    static var trackStrong: NSColor { dynamic(light: 0xD6D6DE, dark: 0x43434A) }
    static var rowAltFill: NSColor { dynamic(light: 0xF0F0F3, dark: 0x303035) }
    static var hairline: NSColor { dynamic(light: 0xE8E8ED, dark: 0x313136) }
    static var gridLine: NSColor { dynamic(light: 0xECECF1, dark: 0x3A3A40) }

    static var uncachedCardFill: NSColor { dynamic(light: 0xEBF1FA, dark: 0x262E39) }
    static var cacheCardFill: NSColor { dynamic(light: 0xE9F2F1, dark: 0x243130) }
    static var outputCardFill: NSColor { dynamic(light: 0xEEEDF8, dark: 0x2D2B39) }
    static var requestCardFill: NSColor { dynamic(light: 0xF8EFEB, dark: 0x332C27) }
    static var cacheStackFill: NSColor { dynamic(light: 0x8FC7C3, dark: 0x2C6B65) }

    /// 同比上行（warn 墨色）/ 下行（ok 墨色）
    static var warnInk: NSColor { dynamic(light: 0x8A5A06, dark: 0xF0CF82) }
    static var okInk: NSColor { dynamic(light: 0x116F33, dark: 0x6EE7B7) }
    static var okColor: NSColor { dynamic(light: 0x14913F, dark: 0x34D399) }

    // MARK: 文本（沿用面板语义色）

    static var secondaryText: NSColor { MenuPanelStyle.secondaryText }
    static var tertiaryText: NSColor { MenuPanelStyle.tertiaryText }
    static var selectedFill: NSColor { MenuPanelStyle.subtleFill }
    static var currentHourWash: NSColor { MenuPanelStyle.accentColor.withAlphaComponent(0.10) }
    static var accentText: NSColor { MenuPanelStyle.accentColor }

    // MARK: 尺寸

    static let cardInset: CGFloat = 10
    static let cardRadius: CGFloat = 9
    static let cardPaddingX: CGFloat = 7
    static let cardPaddingY: CGFloat = 4
    /// 主图高度
    static let bucketChartHeight: CGFloat = 22
    /// 二级页主图高度
    static let detailChartHeight: CGFloat = 70
    /// 迷你 sparkline 高度（分族卡标题行右侧的小走势条）
    static let sparkHeight: CGFloat = 12
    /// 分族卡标题行右侧走势条宽度
    static let cardSparkWidth: CGFloat = 54
    /// 天趋势高度
    static let trendHeight: CGFloat = 20
    /// 状态带高度
    static let stateBandHeight: CGFloat = 20
    /// 环形图直径 / 环宽（环内数字提到 10.5pt 后同步放大）
    static let ringSize: CGFloat = 34
    static let ringWidth: CGFloat = 3.6
    /// 分布条高度
    static let stackBarHeight: CGFloat = 7

    // MARK: 首屏区块高度（320×520 面板预算：pane 可用 458pt）

    /// Hero 区高度
    static let heroHeight: CGFloat = 46
    /// 四族卡高度（标题行 + 主数值 + 一行辅助）
    static let familyCardHeight: CGFloat = 59
    /// 主面板分布行高度（两行：名称 / 数值·占比）
    static let distroRowHeight: CGFloat = 26
    /// 二级页分布行高度（单行，整行宽度可用）
    static let distroDetailRowHeight: CGFloat = 16
    /// 分布行数值列宽（右对齐）
    static let distroValueWidth: CGFloat = 44
    /// 兼容旧成员
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
        case 0: return uncachedColor
        case 1: return outputColor
        case 2: return cacheColor
        default: return requestColor
        }
    }

    static func metricInk(_ index: Int) -> NSColor {
        switch index {
        case 0: return uncachedInk
        case 1: return outputInk
        case 2: return cacheInk
        default: return requestInk
        }
    }

    static func metricCardFill(_ index: Int) -> NSColor {
        switch index {
        case 0: return uncachedCardFill
        case 1: return outputCardFill
        case 2: return cacheCardFill
        default: return requestCardFill
        }
    }

    /// 分布条配色：按序号轮转（项目 / 模型共用同一取色函数）
    static func distroColor(_ index: Int) -> NSColor {
        switch index % 6 {
        case 0: return uncachedColor
        case 1: return cacheColor
        case 2: return outputColor
        case 3: return requestColor
        case 4: return ghostColor
        default: return trackStrong
        }
    }

    /// 色值 → 动态 NSColor（浅色 / 深色各写一次）
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return hex(darkMode ? dark : light)
        }
    }

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1)
    }

    static func translucent(_ alpha: CGFloat) -> NSColor { MenuPanelStyle.dynamicLabel(alpha: alpha) }

    static func blend(_ base: NSColor, with other: NSColor, accentRatio: CGFloat) -> NSColor {
        let a = base.usingColorSpace(.sRGB) ?? base
        let b = other.usingColorSpace(.sRGB) ?? other
        return NSColor(srgbRed: a.redComponent * accentRatio + b.redComponent * (1 - accentRatio),
                       green: a.greenComponent * accentRatio + b.greenComponent * (1 - accentRatio),
                       blue: a.blueComponent * accentRatio + b.blueComponent * (1 - accentRatio),
                       alpha: 1)
    }

    static func modelColor(_ index: Int) -> NSColor { distroColor(index) }
}
