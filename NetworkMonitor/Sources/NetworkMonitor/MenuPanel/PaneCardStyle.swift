import AppKit

// MARK: - 面板共用卡片语言（唯一来源）

/// 面板卡片语言 —— 额度页与 Token 页共用同一套底色 / 圆角 / 内边距 / 间距 / 字号梯度
///
/// 存在理由：两页此前各写一份（`MenuPanelStyle.subtleFill`+8pt 圆角 vs
/// `TokenPaneStyle.cardFill`+9pt 圆角、16 vs 24 的最大字号），同一屏两套公式，
/// 用户实测反馈「两个页面的风格不搭配」。收敛后：
/// - 颜色 / 字号 / 尺寸**只在这里定义一次**；
/// - `TokenPaneStyle` 与 `BillingPaneStyle` 保留同名成员作为**转发**，调用点不必改；
/// - 新增取值一律先来这里加，禁止在页面里另写一份。
@MainActor
enum PaneCardStyle {

    // MARK: 卡片几何（两页完全一致）

    /// 卡片圆角
    static let cardRadius: CGFloat = 9
    /// 卡片左右内边距
    static let cardPaddingX: CGFloat = 7
    /// 卡片上下内边距
    static let cardPaddingY: CGFloat = 4
    /// 卡片间距（主栈）
    static let cardSpacing: CGFloat = 4
    /// 卡片内行距
    static let rowSpacing: CGFloat = 2
    /// 自适应卡片（二级页 / 展开区）内边距
    static let boxPaddingX: CGFloat = 9
    static let boxPaddingY: CGFloat = 7
    /// 卡头行高
    static let cardHeadHeight: CGFloat = 13

    // MARK: 字号梯度（两页同一张表）

    /// Hero 主数值（24pt 等宽粗体）— 两页各自的最大字号
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
    /// Hero 单位（11pt 等宽半粗）
    static let heroUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// 卡内主数值（19pt 等宽粗体）
    static let cardValueFont = NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .bold)
    /// 卡主数值（降一档：15pt 等宽粗体）—— 长数值（7–9 字符）用这一档
    static let cardValueCompactFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
    /// 卡主数值（最紧档：13pt 等宽粗体）—— 极长数值（≥10 字符）用这一档
    static let cardValueDenseFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    /// 卡主数值的单位（9.5pt 等宽半粗，比数值低两档）
    static let cardValueUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    /// 页头主体名 / 卡标题（11pt 粗体）
    static let cardTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// 卡头说明（10pt 等宽）
    static let metaFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 行名（10.5pt）
    static let rowNameFont = NSFont.systemFont(ofSize: 10.5)
    /// 行值（10.5pt 等宽）
    static let rowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// 行值强调（10.5pt 等宽粗体）
    static let rowValueStrongFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
    /// 坐标轴（8.5pt 等宽）
    static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
    /// 图例（10pt 半粗）
    static let legendFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 图例数值（10pt 等宽半粗）
    static let legendValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 状态胶囊（9.5pt 半粗）
    static let chipFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    /// 分段按钮（10.5pt 半粗 / 选中粗体）
    static let segmentFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let segmentSelectedFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)

    // MARK: 五页统一令牌（v2：网络 / 剪贴板 / 传送 / 额度 / Token / 系统共用）

    /// 分区标题 === 卡片标题（统一 11pt 粗体）
    ///
    /// 此前网络 / 剪贴板 / 传送 / 系统用 10pt 半粗、额度 / Token 用 11pt 粗体，
    /// 同屏切换时标题层级对不上；两档收敛到一档，只保留这一个取值。
    static let sectionTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// 列表行高（条目 / 进程 / 设备…）
    ///
    /// 原 32pt（剪贴板 / 传送）比 28pt（进程）高一档，同屏两套行距；统一到 28pt。
    static let rowHeight: CGFloat = 28
    /// 紧凑行高（进程行）
    static let compactRowHeight: CGFloat = 26
    /// 次速率数字（网络页上行）
    static let sideValueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

    // MARK: 页面尺寸

    /// 页头行高（五页一致：主体名 + 弹簧 + 页级分段 / 时间戳 / 刷新）
    static let pageHeadHeight: CGFloat = 22
    /// 页头 / 状态带左右内边距（此前 7 / 8 / 12 混用）
    static let bandPaddingX: CGFloat = 7
    /// 状态带圆角（此前 6 / 8 混用）
    static let bandRadius: CGFloat = 6
    /// 状态带组间距（键值对之间）
    static let bandGroupSpacing: CGFloat = 8
    /// 状态带组内间距（键与值之间）
    static let bandInnerSpacing: CGFloat = 3
    /// Hero 区高度
    static let heroHeight: CGFloat = 46
    /// 状态带高度
    static let stateBandHeight: CGFloat = 20
    /// 主图柱高（首屏）
    static let bucketChartHeight: CGFloat = 22
    /// 展开区主图柱高
    static let expandedChartHeight: CGFloat = 44
    /// 迷你折线高度 / 宽度
    static let sparkHeight: CGFloat = 12
    static let sparkWidth: CGFloat = 54
    /// 缓存屏大命中环（主面板卡片内仍是 34pt 小环）
    static let bigRingSize: CGFloat = 72
    static let bigRingWidth: CGFloat = 7
    /// 用量屏主图 / 天趋势高度（整屏独占，第三轮再放大：主图 160 / 趋势 120）
    static let usageChartHeight: CGFloat = 160
    static let usageTrendHeight: CGFloat = 120

    // MARK: 卡片底色

    /// 卡片底（实色面，深浅各写一次）
    static var cardFill: NSColor { dynamic(light: 0xF5F5F7, dark: 0x26262A) }
    /// 状态带 / 胶囊底
    static var bandFill: NSColor { dynamic(light: 0xEEEFF2, dark: 0x2B2B30) }
    /// 图表轨道
    static var trackColor: NSColor { dynamic(light: 0xE4E4EA, dark: 0x39393F) }
    /// 强轨道（分布条剩余段）
    static var trackStrong: NSColor { dynamic(light: 0xD6D6DE, dark: 0x43434A) }
    /// 1pt 分隔线
    static var hairline: NSColor { dynamic(light: 0xE8E8ED, dark: 0x313136) }
    /// 图表网格线
    static var gridLine: NSColor { dynamic(light: 0xECECF1, dark: 0x3A3A40) }
    /// 选中态底（分段 / 悬停）
    static var selectedFill: NSColor { MenuPanelStyle.subtleFill }
    /// 四族卡底（Token 页用）
    static var uncachedCardFill: NSColor { dynamic(light: 0xEBF1FA, dark: 0x262E39) }
    static var cacheCardFill: NSColor { dynamic(light: 0xE9F2F1, dark: 0x243130) }
    static var outputCardFill: NSColor { dynamic(light: 0xEEEDF8, dark: 0x2D2B39) }
    static var requestCardFill: NSColor { dynamic(light: 0xF8EFEB, dark: 0x332C27) }

    // MARK: 四族语义色 + 告警色（两页共用）

    static var uncachedColor: NSColor { dynamic(light: 0x0071E3, dark: 0x409CFF) }
    static var uncachedInk: NSColor { dynamic(light: 0x0058B3, dark: 0x6FB6FF) }
    static var cacheColor: NSColor { dynamic(light: 0x0D9488, dark: 0x2DD4BF) }
    static var cacheInk: NSColor { dynamic(light: 0x0B6D64, dark: 0x5CE3D2) }
    static var outputColor: NSColor { dynamic(light: 0x5B5BD6, dark: 0xA89DFF) }
    static var outputInk: NSColor { dynamic(light: 0x4A44B8, dark: 0xBFB6FF) }
    static var requestColor: NSColor { dynamic(light: 0xC2410C, dark: 0xFF8A4C) }
    static var requestInk: NSColor { dynamic(light: 0xA83A0B, dark: 0xFFAB7D) }
    static var cacheStackFill: NSColor { dynamic(light: 0x8FC7C3, dark: 0x2C6B65) }
    /// 对照 / 占位灰
    static var ghostColor: NSColor { dynamic(light: 0xB4B4BE, dark: 0x6A6A72) }
    /// 告警墨色（额度不足一半）
    static var warnInk: NSColor { dynamic(light: 0x8A5A06, dark: 0xF0CF82) }
    /// 正常墨色（额度充足 / 同比下行）
    static var okInk: NSColor { dynamic(light: 0x116F33, dark: 0x6EE7B7) }
    /// 达标主色（进度条正常段）
    static var okColor: NSColor { dynamic(light: 0x14913F, dark: 0x34D399) }

    // MARK: 文本（沿用面板语义色）

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { MenuPanelStyle.secondaryText }
    static var tertiaryText: NSColor { MenuPanelStyle.tertiaryText }
    static var accentText: NSColor { MenuPanelStyle.accentColor }

    // MARK: 工具

    /// 色值 → 动态 NSColor（深浅各写一次；视图在 draw 阶段解析，切换外观实时跟随）
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
}
