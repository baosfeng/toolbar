import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 设置窗口令牌层（唯一出口）

/// 设置窗口的令牌唯一出口 —— 颜色转发 `ThemeStyle` 语义角色，几何与字号取定稿度量表
///
/// 设计契约：`docs/设计/设置窗口-视觉统一-设计规格.md`；定稿度量见
/// `.open-design/settings-redesign/04-notes.md` §2「D 定稿度量表」。
/// 三件同源：**同一取色源**（`ThemeStyle` 的角色，不再直接引用系统语义色）、
/// **同一卡形**（cardFill 实底 + 圆角 9 + 0.5pt `cardStroke` + 顶部 1pt `cardHighlight`）、
/// **同一层级逻辑**（页头 17 → 分组 11.5 semibold → 卡头 11.5 粗 → 行名 12 / 行值 11.5 等宽），
/// 字号按窗口尺度比面板每档 +1.5pt。
///
/// 度量数值不在这里写：`SettingsSkeletonMetrics`（UI 库，可单测）是唯一真源，
/// 本文件只负责把数值转成 AppKit 的类型（`NSFont` / `NSColor` / `NSSize`）。
///
/// 颜色一律写成「每次访问重新构造的动态 `NSColor`」（照 `ThemeStyle.color` 的写法）：
/// 创建瞬间解析成静态值（如存成 `CGColor`）会残留旧主题色，换主题后整窗只有部分元素变。
@MainActor
enum SettingsTheme {

    // MARK: - 窗口与侧栏（数值转发度量层）

    /// 窗口尺寸（与原型画布一致）
    static let windowSize = NSSize(width: SettingsSkeletonMetrics.windowWidth,
                                   height: SettingsSkeletonMetrics.windowHeight)
    /// 侧栏宽度
    static let sidebarWidth = SettingsSkeletonMetrics.sidebarWidth
    /// 侧栏导航项高
    static let sidebarItemHeight = SettingsSkeletonMetrics.sidebarItemHeight
    /// 侧栏导航项圆角
    static let sidebarItemRadius: CGFloat = 6
    /// 侧栏图标字号（SF Symbol 点位）
    static let sidebarIconSize: CGFloat = 14
    /// 侧栏左右内边距
    static let sidebarInset: CGFloat = 8
    /// 侧栏顶部内边距
    static let sidebarTopInset: CGFloat = 10
    /// 侧栏段头与上方内容的间距（首段贴顶，取更小的一档）
    static let sidebarGroupSpacing: CGFloat = 10
    static let sidebarGroupSpacingFirst: CGFloat = 4
    /// 侧栏段头与下方导航项的间距
    static let sidebarGroupGap: CGFloat = 3
    /// 品牌行高度
    static let brandRowHeight: CGFloat = 28

    // MARK: - 内容区

    /// 内容区左右内边距（窗口边缘 → 页内容）
    static let contentInset = SettingsSkeletonMetrics.contentInset

    // MARK: - 卡片

    /// 卡片圆角（与 `PaneCardStyle.cardRadius` 同档）
    static let cardRadius = SettingsSkeletonMetrics.cardRadius
    /// 卡片左右内边距（行自己吃这一档，卡片本体左右为 0）
    static let cardPaddingX = SettingsSkeletonMetrics.cardPaddingX
    /// 卡片上下内边距
    static let cardPaddingY = SettingsSkeletonMetrics.cardPaddingY
    /// 相邻卡片间距
    static let cardSpacing = SettingsSkeletonMetrics.cardSpacing
    /// 卡片描边宽度
    static let cardStrokeWidth: CGFloat = 0.5
    /// 卡头高度（仅需要口径的卡：Provider 名、菜单栏指标「第 N 项」）
    static let cardHeadHeight: CGFloat = 13

    // MARK: - 分组与行

    /// 分组标题上方间距
    static let groupSpacingTop = SettingsSkeletonMetrics.groupSpacingTop
    /// 分组标题下方间距
    static let groupSpacingBottom = SettingsSkeletonMetrics.groupSpacingBottom
    /// 分组标题左右内缩（与定稿的 2pt 内缩一致）
    static let groupTitleInset: CGFloat = 2
    /// 行最小高
    static let rowHeight = SettingsSkeletonMetrics.rowHeight
    /// 行上下内边距（行里带副标题时靠它撑高）
    static let rowPaddingY = SettingsSkeletonMetrics.rowPaddingY
    /// 行名与副名间距
    static let rowLabelSpacing: CGFloat = 1
    /// 页尾说明与上文间距
    static let noteSpacing = SettingsSkeletonMetrics.cardSpacing
    /// 相邻页尾说明间距
    static let noteGap: CGFloat = 4

    // MARK: - 状态带与页头胶囊

    /// 状态带 / 胶囊高度
    static let statusBandHeight = SettingsSkeletonMetrics.statusBandHeight
    /// 状态带 / 胶囊圆角
    static let statusBandRadius = SettingsSkeletonMetrics.statusBandRadius
    /// 状态带左右内边距
    static let statusBandPaddingX: CGFloat = 8
    /// 胶囊左右内边距
    static let statusChipPaddingX: CGFloat = 9
    /// 状态点直径
    static let statusDotSize: CGFloat = 7
    /// 状态点与文案间距
    static let statusDotSpacing: CGFloat = 6
    /// 页头标题与胶囊的间距
    static let statusChipSpacing: CGFloat = 10

    // MARK: - 控件

    /// 控件高（下拉 / 按钮 / 分段）
    static let controlHeight: CGFloat = 22

    // MARK: - 字号（窗口档；字号是 AppKit 类型，故留在本层）

    /// 页头标题（17pt 粗）
    static let pageTitleFont = NSFont.systemFont(ofSize: 17, weight: .bold)
    /// 页头说明（11.5pt 次级）
    static let pageSubtitleFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    /// 分组标题（11.5pt semibold，中文不转大写）
    static let sectionTitleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    /// 卡头（11.5pt 粗）
    static let cardHeadFont = NSFont.systemFont(ofSize: 11.5, weight: .bold)
    /// 卡头右侧口径（10.5pt 等宽）
    static let cardMetaFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// 行名（12pt）
    static let rowTitleFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    /// 行副名（11pt）
    static let rowSubtitleFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    /// 行值（11.5pt 等宽）
    ///
    /// 行值字体仍由 trailingStack 里的控件自己定（开关 / 下拉各有一套），
    /// 这里给调用方一个统一档：只读数值一律用它，避免每个页面自己写 11 / 12 / 12.5。
    static let rowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
    /// 行值强调（11.5pt 等宽半粗）
    static let rowValueStrongFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    /// 页尾说明（11pt）
    static let noteFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    /// 侧栏导航项（12pt；选中加粗一档）
    static let sidebarItemFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let sidebarItemSelectedFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    /// 侧栏段头（10.5pt semibold）
    static let sidebarGroupFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    /// 侧栏品牌名（12.5pt semibold）
    static let brandFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    /// 页头胶囊文案（10.5pt 等宽）
    static let statusChipFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// 状态带键（10pt 等宽三级色）
    static let statusBandKeyFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 状态带值（10.5pt 等宽半粗）
    static let statusBandValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

    // MARK: - 颜色（全部转发主题语义角色）

    /// 窗口底 / 侧栏底 / 内容区底
    static var surface: NSColor { ThemeStyle.color(.surface) }
    /// 卡片底
    static var cardFill: NSColor { ThemeStyle.color(.cardFill) }
    /// 卡片描边（角色自带 10% 透明度）
    static var cardStroke: NSColor { ThemeStyle.color(.cardStroke) }
    /// 卡片顶部高光
    static var cardHighlight: NSColor { ThemeStyle.color(.cardHighlight) }
    /// 1pt 分隔线：卡内行分隔线与侧栏竖线共用
    static var hairline: NSColor { ThemeStyle.color(.hairline) }
    /// 悬停 / 选中底（侧栏项）
    static var selectedFill: NSColor { ThemeStyle.color(.selectedFill) }
    /// 状态带 / 胶囊底
    static var bandFill: NSColor { ThemeStyle.color(.bandFill) }
    /// 文字三档
    static var textPrimary: NSColor { ThemeStyle.color(.textPrimary) }
    static var textSecondary: NSColor { ThemeStyle.color(.textSecondary) }
    static var textTertiary: NSColor { ThemeStyle.color(.textTertiary) }
    /// 强调（选中文字与图标、链接、开关开态）
    static var accent: NSColor { ThemeStyle.color(.accent) }
    /// 达标墨色
    static var okInk: NSColor { ThemeStyle.color(.okInk) }
    /// 告警墨色
    static var warnInk: NSColor { ThemeStyle.color(.warnInk) }
    /// 停用 / 中性占位
    static var ghost: NSColor { ThemeStyle.color(.ghost) }

    /// 破坏性动作（清空 / 删除）—— 红的语义是「不可撤销」，与主题无关，
    /// 因此**不进 `ThemeRole`**（给角色表加红等于把系统语义色又引回令牌层）。
    static var destructive: NSColor { .systemRed }

    /// 卡内行分隔线（= hairline；单独出口是为了让「行分隔线」这条用途可被检索到）
    static var rowSeparator: NSColor { hairline }

    // MARK: - 卡片三件套的 alpha（取当前主题材质配方）

    /// 卡片顶部高光 alpha
    ///
    /// 取主题的 `material.highlightAlpha`，**不跟随玻璃开关**：设置窗口不套玻璃材质，
    /// 卡形强度要跟着「主题」走，不能因为用户关了玻璃就变成没有高光的平卡。配方为 0 时兜底。
    static var cardHighlightAlpha: CGFloat {
        let value = CGFloat(ThemeStyle.current.material.highlightAlpha)
        return value > 0 ? value : 0.55
    }

    /// 卡片描边 alpha（兜底 0.10，理由同上）
    static var cardStrokeAlpha: CGFloat {
        let value = CGFloat(ThemeStyle.current.material.strokeAlpha)
        return value > 0 ? value : 0.10
    }

    // MARK: - 绘制

    /// 画一张设置卡：cardFill 实底 + 圆角 9 + 0.5pt cardStroke + 顶部 1pt cardHighlight
    ///
    /// 与面板 `ThemeStyle.drawCard` 的唯一差别是底色**不乘 `cardFillAlpha`**：
    /// 设置窗口是普通窗口（不套玻璃），卡底必须是主题实色；
    /// 乘了半透明会让窗口底透上来，像素上既不是 cardFill 也不是 surface。
    static func drawCardBackground(in bounds: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cardRadius, yRadius: cardRadius)
        cardFill.setFill()
        path.fill()

        // 顶部 1pt 高光：裁到卡片路径里画，圆角处不会溢出
        if bounds.height > 2, cardHighlightAlpha > 0, let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            path.addClip()
            cardHighlight.withAlphaComponent(cardHighlightAlpha).setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            context.restoreGraphicsState()
        }

        if cardStrokeAlpha > 0 {
            cardStroke.withAlphaComponent(cardStrokeAlpha).setStroke()
            // 内缩 0.25pt：0.5pt 线宽正好落在卡片边界内，不会画到隔壁像素
            let strokePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                          xRadius: cardRadius, yRadius: cardRadius)
            strokePath.lineWidth = cardStrokeWidth
            strokePath.stroke()
        }
    }

    /// 画状态带 / 胶囊底（bandFill + 圆角 6）
    static func drawStatusBand(in bounds: NSRect) {
        bandFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: statusBandRadius,
                     yRadius: statusBandRadius).fill()
    }

    // MARK: - 状态点语义

    /// 状态点颜色 —— 只有三种语义（达标 / 告警 / 中性），不引入第四种
    ///
    /// 三态 → 角色的映射是 UI 库里的纯函数（`SettingsStatusTone.themeRole`，可有单测）：
    /// 穷尽 switch，新增语义会编译失败，不会悄悄落到某个默认色。
    static func statusDotColor(_ tone: SettingsStatusTone) -> NSColor {
        ThemeStyle.color(tone.themeRole)
    }
}
