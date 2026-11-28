import CoreGraphics
import Foundation

// MARK: - 卡片几何与命中（纯逻辑）

/// 剪贴板卡片的几何口径 —— 纯函数，不含 AppKit，供自绘卡片与 TestRunner 共用
///
/// 版式对标 Paste 的三段式（设计定稿见 `.open-design/drafts/paste-r2/00-pick.md`）：
///
/// ```
/// ┌──────────────────────────┐  ← 卡头 26pt（来源 App 主题色）
/// │ 类型名      3 分钟前 [icon]│
/// ├──────────────────────────┤
/// │                          │  ← 卡身（正文 / 缩略图）
/// │                          │
/// ├──────────────────────────┤  ← 1pt 发丝线
/// │ 标题            ★ ⌘1     │  ← 卡脚 34pt（标题 + 来源 + 收藏 + 直选提示）
/// │ 来源 · 68 字             │
/// └──────────────────────────┘
/// ```
///
/// 坐标系为翻转视图坐标（y 向下，与卡片 `isFlipped = true` 一致）。
public enum ClipboardCardGeometry {

    /// 几何令牌（视图侧转发本结构，测试直接断言语义）
    public struct Metrics: Equatable, Sendable {
        /// 卡片左右与底部内边距
        public var padding: CGFloat
        /// 卡脚高度（标题行 + 来源行）
        public var footerHeight: CGFloat
        /// 卡身与卡头 / 卡脚之间的留白
        public var bodyGap: CGFloat
        /// 卡脚标题行里收藏星边长
        public var starSize: CGFloat
        /// 卡脚两行之间的间距
        public var footerRowGap: CGFloat

        public init(padding: CGFloat, footerHeight: CGFloat, bodyGap: CGFloat,
                    starSize: CGFloat, footerRowGap: CGFloat) {
            self.padding = padding
            self.footerHeight = footerHeight
            self.bodyGap = bodyGap
            self.starSize = starSize
            self.footerRowGap = footerRowGap
        }

        /// 与 `ClipboardCardView` 同名常量同源（设计规格冻结值）
        public static let standard = Metrics(padding: 10, footerHeight: 34, bodyGap: 6,
                                             starSize: 11, footerRowGap: 1)
    }

    // MARK: 卡片尺寸（随面板高度自适应）

    /// 设计基准卡高：面板高度下限时卡片正好是这个尺寸
    public static let baseCardHeight: CGFloat = 198
    /// 设计基准卡宽（227 × 198，比例 1.15 —— 对标 Paste 的 243 × 212）
    ///
    /// 改造前 176 × 198（0.89）是竖长条：卡身能塞的正文行数少、卡头那行字挤。
    /// 换成接近 Paste 的横长比例后，同样的卡高能多放两行正文，页脚两行也松得开。
    public static let baseCardWidth: CGFloat = 227
    /// 卡片宽度上限：只防超大屏（6K）上单张卡长得像海报，不再参与常规屏的宽度决策
    ///
    /// 上一档写 260 时，366pt 高的面板会先算出 316pt 的卡高、再被 260 截断宽度，
    /// 结果是一张 260×316 的**竖卡**——设计基准给的 1.15 横卡比例在默认面板高度下根本没生效。
    /// 放开到 360 后宽度重新由「卡高 × 比例」决定，一屏张数交给面板高度（高度三档）去调，
    /// 这两个旋钮不再互相踩。
    public static let maxCardWidth: CGFloat = 360
    /// 卡片宽高比（宽 / 高）——只由设计基准给出，面板高度变化时按它等比缩放
    public static var aspectRatio: CGFloat { baseCardWidth / baseCardHeight }
    /// 卡片区顶部留白：卡片贴卡片区上沿，只留 8pt 呼吸
    public static let cardInsetTop: CGFloat = 8
    /// 卡片区底部留白：面板底边到卡片底边（状态胶囊浮在这条带里，对标 Paste 底部 44pt 的收敛版）
    public static let cardInsetBottom: CGFloat = 24
    /// 卡片区在整卡之外的上下留白合计（面板高度下限按它算）
    public static var cardSlack: CGFloat { cardInsetTop + cardInsetBottom }
    /// 卡片高度下限 / 上限：再矮就装不下卡头 + 卡身 + 卡脚，再高就退化成「一屏两张」
    public static let minCardHeight: CGFloat = 150
    public static let maxCardHeight: CGFloat = 440

    /// 设计基准尺寸
    public static var baseSize: CGSize {
        CGSize(width: baseCardWidth, height: baseCardHeight)
    }

    /// 卡片高度：卡片区高度扣掉上下留白（面板变矮 → 卡变小 → 一屏多几张，Paste 的 Compact Mode 同口径）
    public static func cardHeight(forCardAreaHeight height: CGFloat) -> CGFloat {
        let raw = height.isFinite ? height - cardSlack : baseCardHeight
        return min(max(raw, minCardHeight), maxCardHeight)
    }

    /// 卡片尺寸：高度吃掉卡片区（扣掉上下留白），宽度按基准宽高比等比给出
    ///
    /// 只改尺寸、不改行数口径：卡片永远单行横向排列，一屏能放几张由面板宽与卡宽决定。
    /// 面板越高 → 卡越高 → 卡越宽 → 一屏越少（与 Paste「高度变化 = 卡片预览变大变小」同口径）；
    /// 想一屏多张就切面板高度档位（ClipboardPanelSize），而不是压缩宽度把卡片挤成竖条。
    /// 宽度封顶后不反推高度：反推会让面板一高，卡片就缩成「上下各留一大截」的孤岛。
    public static func cardSize(forCardAreaHeight height: CGFloat) -> CGSize {
        let h = cardHeight(forCardAreaHeight: height).rounded()
        let w = min((h * aspectRatio).rounded(), maxCardWidth)
        return CGSize(width: w, height: h)
    }

    // MARK: 卡头带

    /// 卡头带高度 —— 按来源 App 染色的那条横带（贴卡顶、与卡同宽）
    ///
    /// 26pt 是「类型名 + 相对时间 + 来源 App 图标」三者单行放得下的最小档（对标 Paste 的彩色卡头）：
    /// 20pt 时这条带退化成一根线、认不出来源；32pt 时 176pt 卡宽放不下时间、被折成两行。
    public static let headBandHeight: CGFloat = 26
    /// 卡头带内左右内边距
    public static let bandPaddingX: CGFloat = 8
    /// 卡头带与卡身之间的留白（头带是一块颜色面，正文不能贴上去）
    public static let bandBodyGap: CGFloat = 6
    /// 卡头带里的来源 App 图标边长（比卡脚的小图标大一档：它是色带上的视觉锚点）
    public static let bandIconSize: CGFloat = 14
    /// 卡头带内元素间距
    public static let bandGap: CGFloat = 5

    /// 卡头带矩形：贴卡片上沿、与卡同宽（圆角由绘制侧按卡体裁切）
    public static func headBandRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headBandHeight)
    }

    // MARK: 三段矩形

    /// 卡脚矩形（贴卡底、与卡同宽，顶部画一条发丝线）
    public static func footerRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        CGRect(x: bounds.minX,
               y: bounds.maxY - metrics.footerHeight,
               width: bounds.width,
               height: metrics.footerHeight)
    }

    /// 卡身矩形 = 卡头之下、卡脚之上，左右内缩 padding
    public static func contentRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        let top = headBandHeight + bandBodyGap
        let bottom = footerRect(in: bounds, metrics: metrics).minY - metrics.bodyGap
        return CGRect(x: bounds.minX + metrics.padding,
                      y: bounds.minY + top,
                      width: max(0, bounds.width - metrics.padding * 2),
                      height: max(0, bottom - (bounds.minY + top)))
    }

    /// 正文区 = 卡身（图片卡的缩略图铺满这一块）
    public static func bodyRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        contentRect(in: bounds, metrics: metrics)
    }

    /// 缩略图区域 = 卡身（等比填充裁剪在绘制侧决定）
    public static func thumbnailRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        bodyRect(in: bounds, metrics: metrics)
    }

    /// 卡脚标题行矩形（左右内缩 padding，贴着卡脚顶部留一点呼吸）
    public static func footerTitleRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        let footer = footerRect(in: bounds, metrics: metrics)
        let top = footer.minY + 6
        return CGRect(x: footer.minX + metrics.padding,
                      y: top,
                      width: max(0, footer.width - metrics.padding * 2),
                      height: 15)
    }

    /// 卡脚来源行矩形（标题行之下）
    public static func footerSourceRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        let title = footerTitleRect(in: bounds, metrics: metrics)
        return CGRect(x: title.minX,
                      y: title.maxY + metrics.footerRowGap,
                      width: title.width,
                      height: 11)
    }

    /// 卡脚顶部那条发丝线的纵坐标
    public static func footerHairlineY(in bounds: CGRect, metrics: Metrics = .standard) -> CGFloat {
        footerRect(in: bounds, metrics: metrics).minY
    }

    /// 收藏星位置：卡脚标题行最右，行内垂直居中
    ///
    /// 星标不再与 ⌘N 争同一条线：⌘N 是「快速粘贴」的键位提示，落在来源行右侧，
    /// 星标是「收藏」的状态标记，落在标题行右侧 —— 两者语义不同，不该挤在一起。
    public static func starRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        let title = footerTitleRect(in: bounds, metrics: metrics)
        return CGRect(x: title.maxX - metrics.starSize,
                      y: title.midY - metrics.starSize / 2,
                      width: metrics.starSize, height: metrics.starSize)
    }

    /// 收藏星的命中框：视觉 11pt 的星太难点，命中区扩到 24pt 见方（hover 出现的「点一下就收藏」入口）
    ///
    /// 命中区以星标中心为中心，并夹在卡脚矩形内：星标贴卡脚右边缘时命中区向左收，
    /// 仍保持 24pt 见方（不为了贴边把可点面积砍掉一半）。
    public static func starHitRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        let star = starRect(in: bounds, metrics: metrics)
        let footer = footerRect(in: bounds, metrics: metrics)
        let side: CGFloat = 24
        let x = min(max(star.midX - side / 2, footer.minX), max(footer.minX, footer.maxX - side))
        let y = min(max(star.midY - side / 2, footer.minY), max(footer.minY, footer.maxY - side))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// Paste Stack 角标：贴卡身右上角（尺寸随编号宽度，不挤占正文布局）
    public static func badgeRect(in bounds: CGRect, badgeSize: CGSize,
                                 metrics: Metrics = .standard) -> CGRect {
        let content = contentRect(in: bounds, metrics: metrics)
        return CGRect(x: content.maxX - badgeSize.width, y: content.minY,
                      width: badgeSize.width, height: badgeSize.height)
    }

    /// ⌘N 文案（1…9 之外返回 nil）
    public static func shortcutText(number: Int?) -> String? {
        guard let number, (1...9).contains(number) else { return nil }
        return "⌘\(number)"
    }
}

// MARK: - 命中区域

/// 卡片内被点中的区域（自绘后没有子视图可分配事件，命中判定要自己重做）
public enum ClipboardCardHitRegion: Equatable, Sendable {
    /// 卡身（图片卡的缩略图 / 文本卡正文）
    case thumbnail
    /// 卡脚标题行里的收藏星
    case star
    /// Paste Stack 角标
    case badge
    /// 卡脚（标题 + 来源）
    case meta
    /// 卡头带（类型 + 时间 + 来源图标）
    case headBand
    /// 卡身（文本卡）
    case body
}

/// 命中后的卡片动作
public enum ClipboardCardHitAction: Equatable, Sendable {
    /// 单击：选中该条
    case select
    /// 单击星标：收藏 / 取消收藏（不选中、不粘贴）
    case togglePin
    /// 双击：直接粘贴
    case paste
    /// 右键：弹出五项菜单
    case showMenu
}

/// 卡片命中测试 —— 纯函数，与绘制共用同一套几何口径
///
/// 语义与改造前的视图树一致：星标 / 角标 / 卡头 / 卡身 / 卡脚都是**整卡的一部分**，
/// 双击都粘贴、右键都弹菜单；唯一的例外是**星标单击**——它是「点一下就收藏」的独立入口
/// （对标 Paste hover 出的 ⊕），点它既不选中也不粘贴。
/// 区域本身仍要区分：读屏焦点框、缩略图占位、以及将来给这些区域单独挂动作时都靠它。
public enum ClipboardCardHitTest {

    /// 点所在的区域
    ///
    /// - Parameters:
    ///   - point: 卡片内坐标（flipped）
    ///   - badgeSize: 角标实测尺寸（不显示时 .zero）
    ///   - isImage: 是否为图片条目（决定卡身是 .thumbnail 还是 .body）
    public static func region(at point: CGPoint, in bounds: CGRect,
                              badgeSize: CGSize = .zero,
                              isImage: Bool, metrics: ClipboardCardGeometry.Metrics = .standard)
    -> ClipboardCardHitRegion {
        guard bounds.contains(point) else { return .body }
        // 星标 / 角标压在卡上：按优先级查表（顺序即优先级，空矩形不参与命中）
        // 星标用放大后的命中框：11pt 的图形直接当热区，鼠标要精确到半个字才点得中
        let star = ClipboardCardGeometry.starHitRect(in: bounds, metrics: metrics)
        let badge = badgeSize.width > 0 && badgeSize.height > 0
            ? ClipboardCardGeometry.badgeRect(in: bounds, badgeSize: badgeSize, metrics: metrics) : .zero
        if let index = DrawnHitRegions.priorityIndex(at: point, in: [star, badge]) {
            return index == 0 ? .star : .badge
        }
        if point.y < ClipboardCardGeometry.headBandRect(in: bounds).maxY { return .headBand }
        if point.y >= ClipboardCardGeometry.footerRect(in: bounds, metrics: metrics).minY { return .meta }
        return isImage ? .thumbnail : .body
    }

    /// 区域 + 点击次数 + 按键 → 动作
    ///
    /// 右键永远优先（连点两下再右键仍是菜单）；双击永远粘贴（星标上双击也算「就要这条」）；
    /// 星标单击是唯一与其它区域不同的动作：收藏切换。
    public static func action(for region: ClipboardCardHitRegion,
                              clickCount: Int,
                              isContextMenu: Bool) -> ClipboardCardHitAction {
        if isContextMenu { return .showMenu }
        if clickCount >= 2 { return .paste }
        return region == .star ? .togglePin : .select
    }
}
