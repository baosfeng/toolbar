import AppKit
import NetworkMonitorCore

// MARK: - 面板共用卡片语言（唯一来源）

/// 面板卡片语言 —— 各页共用同一套底色 / 圆角 / 内边距 / 间距 / 字号梯度
///
/// 分层（改造后）：
/// - **几何与字号**只在这里定义（历史原因：本文件是 331 处引用的唯一真源，
///   把它们搬去主题层只会多出第二份，故几何继续留在这里）；
/// - **颜色**一律转发 `ThemeStyle`（语义角色 → 动态 `NSColor`）：换主题只改
///   `ThemeCatalog` 的色表，本文件一行颜色都不写；
/// - `TokenPaneStyle` / `BillingPaneStyle` 保留同名成员作为**转发**，调用点零改动。
///
/// 存在理由（历史）：两页此前各写一份（`MenuPanelStyle.subtleFill`+8pt 圆角 vs
/// `TokenPaneStyle.cardFill`+9pt 圆角、16 vs 24 的最大字号），同一屏两套公式，
/// 用户实测反馈「两个页面的风格不搭配」。收敛后颜色 / 字号 / 尺寸只在令牌层定义一次。
@MainActor
public enum PaneCardStyle {

    // MARK: 卡片几何（六页完全一致）

    /// 卡片圆角
    public static let cardRadius: CGFloat = 9
    /// 卡片左右内边距
    public static let cardPaddingX: CGFloat = 7
    /// 卡片上下内边距
    public static let cardPaddingY: CGFloat = 4
    /// 卡片间距（主栈）
    public static let cardSpacing: CGFloat = 4
    /// 卡片内行距
    public static let rowSpacing: CGFloat = 2
    /// 自适应卡片（二级页 / 展开区）内边距
    public static let boxPaddingX: CGFloat = 9
    public static let boxPaddingY: CGFloat = 7
    /// 自适应卡片（二级页）额外内缩 —— 原 `TokenPaneStyle.cardInset`
    public static let cardInset: CGFloat = 10
    /// 卡头行高
    public static let cardHeadHeight: CGFloat = 13

    // MARK: 字号梯度（六页同一张表）

    /// Hero 主数值（24pt 等宽粗体）— 各页最大的字号
    public static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
    /// Hero 单位（11pt 等宽半粗）
    public static let heroUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// 卡内主数值（19pt 等宽粗体）
    public static let cardValueFont = NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .bold)
    /// 卡主数值（降一档：15pt 等宽粗体）—— 长数值（7–9 字符）用这一档
    public static let cardValueCompactFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
    /// 卡主数值（最紧档：13pt 等宽粗体）—— 极长数值（≥10 字符）用这一档
    public static let cardValueDenseFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    /// 卡主数值的单位（9.5pt 等宽半粗，比数值低两档）
    public static let cardValueUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
    /// 页头主体名 / 卡标题（11pt 粗体）
    public static let cardTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// 卡头说明（10pt 等宽）
    public static let metaFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 行名（10.5pt）
    public static let rowNameFont = NSFont.systemFont(ofSize: 10.5)
    /// 行值（10.5pt 等宽）
    public static let rowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// 行值强调（10.5pt 等宽粗体）
    public static let rowValueStrongFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
    /// 坐标轴（8.5pt 等宽）
    public static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
    /// 图例（10pt 半粗）
    public static let legendFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 图例数值（10pt 等宽半粗）
    public static let legendValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 状态胶囊（9.5pt 半粗）
    public static let chipFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    /// 分段按钮（10.5pt 半粗 / 选中粗体）
    public static let segmentFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    public static let segmentSelectedFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)
    /// 说明段落 / 状态页正文（12pt）—— 原 `TokenPaneStyle.stateBodyFont`
    public static let bodyFont = NSFont.systemFont(ofSize: 12)
    /// 模型名（10.5pt 等宽）—— 原 `BillingPaneStyle.modelNameFont`
    public static let modelNameFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    // MARK: 六页统一令牌

    /// 分区标题 === 卡片标题（统一 11pt 粗体）
    ///
    /// 此前网络 / 剪贴板 / 传送 / 系统用 10pt 半粗、额度 / Token 用 11pt 粗体，
    /// 同屏切换时标题层级对不上；两档收敛到一档，只保留这一个取值。
    public static let sectionTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// 列表行高（条目 / 进程 / 设备…）
    ///
    /// 原 32pt（剪贴板 / 传送）比 28pt（进程）高一档，同屏两套行距；统一到 28pt。
    static let rowHeight: CGFloat = 28
    /// 紧凑行高（进程行）
    static let compactRowHeight: CGFloat = 26
    /// 次速率数字（网络页上行）
    static let sideValueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

    // MARK: 页面尺寸

    /// 页头行高（六页一致：主体名 + 弹簧 + 页级分段 / 时间戳 / 刷新）
    public static let pageHeadHeight: CGFloat = 22
    /// 页头 / 状态带左右内边距（此前 7 / 8 / 12 混用）
    public static let bandPaddingX: CGFloat = 7
    /// 状态带圆角（此前 6 / 8 混用）
    static let bandRadius: CGFloat = 6
    /// 状态带组间距（键值对之间）
    public static let bandGroupSpacing: CGFloat = 8
    /// 状态带组内间距（键与值之间）
    public static let bandInnerSpacing: CGFloat = 3
    /// Hero 区高度
    public static let heroHeight: CGFloat = 46
    /// 状态带高度
    public static let stateBandHeight: CGFloat = 20
    /// 主图柱高（首屏）
    public static let bucketChartHeight: CGFloat = 22
    /// 展开区主图柱高
    static let expandedChartHeight: CGFloat = 44
    /// 迷你折线高度 / 宽度
    public static let sparkHeight: CGFloat = 12
    public static let sparkWidth: CGFloat = 54
    /// 缓存命中环（主面板卡内 / 二级页大环）
    public static let ringSize: CGFloat = 34
    public static let ringWidth: CGFloat = 3.6
    public static let bigRingSize: CGFloat = 72
    public static let bigRingWidth: CGFloat = 7
    /// 用量屏主图 / 天趋势高度（整屏独占）
    public static let usageChartHeight: CGFloat = 160
    public static let usageTrendHeight: CGFloat = 120

    // MARK: 卡片底色（转发主题）

    /// 卡片底（实色面）
    public static var cardFill: NSColor { ThemeStyle.color(.cardFill) }
    /// 状态带 / 胶囊底
    public static var bandFill: NSColor { ThemeStyle.color(.bandFill) }
    /// 图表轨道
    public static var trackColor: NSColor { ThemeStyle.color(.track) }
    /// 强轨道（分布条剩余段）
    public static var trackStrong: NSColor { ThemeStyle.color(.trackStrong) }
    /// 1pt 分隔线
    public static var hairline: NSColor { ThemeStyle.color(.hairline) }
    /// 图表网格线
    public static var gridLine: NSColor { ThemeStyle.color(.grid) }
    /// 选中态底（分段 / 悬停）
    public static var selectedFill: NSColor { ThemeStyle.color(.selectedFill) }
    /// 输入框边框
    public static var fieldBorder: NSColor { .separatorColor }
    /// 四族卡底
    public static var uncachedCardFill: NSColor { ThemeStyle.color(.family1Fill) }
    public static var cacheCardFill: NSColor { ThemeStyle.color(.family2Fill) }
    public static var outputCardFill: NSColor { ThemeStyle.color(.family3Fill) }
    public static var requestCardFill: NSColor { ThemeStyle.color(.family4Fill) }

    // MARK: 四族语义色 + 告警色

    public static var uncachedColor: NSColor { ThemeStyle.color(.family1) }
    public static var uncachedInk: NSColor { ThemeStyle.color(.family1Ink) }
    public static var cacheColor: NSColor { ThemeStyle.color(.family2) }
    public static var cacheInk: NSColor { ThemeStyle.color(.family2Ink) }
    public static var outputColor: NSColor { ThemeStyle.color(.family3) }
    public static var outputInk: NSColor { ThemeStyle.color(.family3Ink) }
    public static var requestColor: NSColor { ThemeStyle.color(.family4) }
    public static var requestInk: NSColor { ThemeStyle.color(.family4Ink) }
    public static var cacheStackFill: NSColor { ThemeStyle.color(.cacheStack) }
    /// 对照 / 占位灰
    public static var ghostColor: NSColor { ThemeStyle.color(.ghost) }
    /// 告警墨色（额度不足一半）
    public static var warnInk: NSColor { ThemeStyle.color(.warnInk) }
    /// 正常墨色（额度充足 / 同比下行）
    public static var okInk: NSColor { ThemeStyle.color(.okInk) }
    /// 达标主色（进度条正常段）
    public static var okColor: NSColor { ThemeStyle.color(.ok) }

    // MARK: 浅底 / 柔和底色（原页级样式自造值，收敛到这里）

    /// 强调色浅底（分段选中 15%）
    public static var accentSoft: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.15) }
    /// 强调色极浅底（当前小时柱 10%）
    public static var accentWash: NSColor {
        // 强调色是动态色：包一层动态闭包，每次解析都重新取，避免创建瞬间固化
        NSColor(name: nil) { _ in NSColor.controlAccentColor.withAlphaComponent(0.10) }
    }
    /// 危险色浅底（错误条 10%）
    public static var dangerSoft: NSColor { NSColor.systemRed.withAlphaComponent(0.10) }

    // MARK: 文本

    public static var primaryText: NSColor { ThemeStyle.color(.textPrimary) }
    public static var secondaryText: NSColor { ThemeStyle.color(.textSecondary) }
    public static var tertiaryText: NSColor { ThemeStyle.color(.textTertiary) }
    public static var accentText: NSColor { ThemeStyle.color(.accent) }
}
