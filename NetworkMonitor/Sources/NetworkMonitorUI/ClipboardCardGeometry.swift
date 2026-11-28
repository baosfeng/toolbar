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
    /// 设计基准卡宽（与基准卡高同一个比例：176 × 198）
    public static let baseCardWidth: CGFloat = 176
    /// 卡片宽高比（宽 / 高）——只由设计基准给出，面板高度变化时按它等比缩放
    public static var aspectRatio: CGFloat { baseCardWidth / baseCardHeight }
    /// 卡片区在整卡之外的上下留白合计（卡片在卡片区里垂直居中前先扣掉它；上下各 8pt）
    public static let cardSlack: CGFloat = 16
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

    /// 卡片尺寸：高度自适应当卡片区，宽度按基准宽高比等比给出
    ///
    /// 只改尺寸、不改行数口径：卡片永远单行横向排列，一屏能放几张由面板宽与卡宽决定。
    public static func cardSize(forCardAreaHeight height: CGFloat) -> CGSize {
        let h = cardHeight(forCardAreaHeight: height).rounded()
        return CGSize(width: (h * aspectRatio).rounded(), height: h)
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
    /// 双击：直接粘贴
    case paste
    /// 右键：弹出五项菜单
    case showMenu
}

/// 卡片命中测试 —— 纯函数，与绘制共用同一套几何口径
///
/// 语义与改造前的视图树一致：星标 / 角标 / 卡头 / 卡身 / 卡脚都是**整卡的一部分**，
/// 所有区域的主键单击都选中、双击都粘贴、右键都弹菜单（没有各自的独立动作）。
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
        let star = ClipboardCardGeometry.starRect(in: bounds, metrics: metrics)
        let badge = badgeSize.width > 0 && badgeSize.height > 0
            ? ClipboardCardGeometry.badgeRect(in: bounds, badgeSize: badgeSize, metrics: metrics) : .zero
        if let index = DrawnHitRegions.priorityIndex(at: point, in: [star, badge]) {
            return index == 0 ? .star : .badge
        }
        if point.y < ClipboardCardGeometry.headBandRect(in: bounds).maxY { return .headBand }
        if point.y >= ClipboardCardGeometry.footerRect(in: bounds, metrics: metrics).minY { return .meta }
        return isImage ? .thumbnail : .body
    }

    /// 区域 + 点击次数 + 按键 → 动作（所有区域口径一致，保证改造前后交互等价）
    ///
    /// - Parameter region: 命中的区域。当前所有区域的动作一致；保留入参让人一眼看出
    ///   「区域不改变动作」是显式约定，而不是漏传。
    public static func action(for region: ClipboardCardHitRegion,
                              clickCount: Int,
                              isContextMenu: Bool) -> ClipboardCardHitAction {
        _ = region
        if isContextMenu { return .showMenu }
        return clickCount >= 2 ? .paste : .select
    }
}
