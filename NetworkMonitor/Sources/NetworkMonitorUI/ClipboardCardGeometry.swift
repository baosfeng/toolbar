import CoreGraphics
import Foundation

// MARK: - 卡片几何与命中（纯逻辑）

/// 剪贴板卡片的几何口径 —— 纯函数，不含 AppKit，供自绘卡片与 TestRunner 共用
///
/// 口径来源（设计与实现一致，改造前后不得漂移）：卡片 176×198、内边距 10、meta 行 16、
/// 正文与 meta 间距 6、类型图标 14、meta 间距 6、收藏星 12。
/// 全部坐标系为翻转视图坐标（y 向下，与卡片 `isFlipped = true` 一致）。
public enum ClipboardCardGeometry {

    /// 几何令牌（视图侧转发本结构，测试直接断言语义）
    public struct Metrics: Equatable, Sendable {
        /// 卡片四边内边距
        public var padding: CGFloat
        /// 底部 meta 行高
        public var metaHeight: CGFloat
        /// 正文区与 meta 行间距
        public var bodyGap: CGFloat
        /// 类型图标边长
        public var typeIconSize: CGFloat
        /// meta 行内元素间距
        public var metaGap: CGFloat
        /// 收藏星边长
        public var starSize: CGFloat

        public init(padding: CGFloat, metaHeight: CGFloat, bodyGap: CGFloat,
                    typeIconSize: CGFloat, metaGap: CGFloat, starSize: CGFloat) {
            self.padding = padding
            self.metaHeight = metaHeight
            self.bodyGap = bodyGap
            self.typeIconSize = typeIconSize
            self.metaGap = metaGap
            self.starSize = starSize
        }

        /// 与 `ClipboardCardView` 同名常量同源（设计规格冻结值）
        public static let standard = Metrics(padding: 10, metaHeight: 16, bodyGap: 6,
                                             typeIconSize: 14, metaGap: 6, starSize: 12)
    }

    // MARK: 矩形

    /// 卡头带高度 —— 按来源 App 染色的那条横带（贴卡顶、与内容区同宽）
    ///
    /// 取内边距同值（10）：头带正好占据卡内上边距，正文区与 meta 行的几何完全不变。
    public static let headBandHeight: CGFloat = 10

    /// 卡头带矩形：贴卡片上沿、与卡同宽，高度吃掉上内边距（圆角由绘制侧按卡体裁切）
    public static func headBandRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headBandHeight)
    }

    /// 内容区（四边内缩 padding）
    public static func contentRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        bounds.insetBy(dx: metrics.padding, dy: metrics.padding)
    }

    /// 正文区（内容区去掉底部 meta 行）
    public static func bodyRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        let content = contentRect(in: bounds, metrics: metrics)
        return CGRect(x: content.minX, y: content.minY, width: content.width,
                      height: max(0, content.height - metrics.metaHeight - metrics.bodyGap))
    }

    /// meta 行的纵向起点（翻转坐标系下为 meta 行顶边）
    public static func metaRowY(in bounds: CGRect, metrics: Metrics = .standard) -> CGFloat {
        contentRect(in: bounds, metrics: metrics).maxY - metrics.metaHeight
    }

    /// meta 行左侧起点：类型图标之后（⌘N 与收藏星从这里开始排）
    public static func metaLeftX(in bounds: CGRect, metrics: Metrics = .standard) -> CGFloat {
        contentRect(in: bounds, metrics: metrics).minX + metrics.typeIconSize + metrics.metaGap
    }

    /// 收藏星位置：类型图标 +（⌘N 宽度 + 间距）之后，meta 行内垂直居中
    ///
    /// - Parameter shortcutWidth: ⌘N 提示的实测宽度（不显示时为 0）
    public static func starRect(in bounds: CGRect, shortcutWidth: CGFloat,
                                metrics: Metrics = .standard) -> CGRect {
        let rowY = metaRowY(in: bounds, metrics: metrics)
        var leftX = metaLeftX(in: bounds, metrics: metrics)
        if shortcutWidth > 0 { leftX += shortcutWidth + metrics.metaGap }
        return CGRect(x: leftX,
                      y: rowY + (metrics.metaHeight - metrics.starSize) / 2,
                      width: metrics.starSize, height: metrics.starSize)
    }

    /// 缩略图区域 = 正文区（等比填充裁剪在绘制侧决定）
    public static func thumbnailRect(in bounds: CGRect, metrics: Metrics = .standard) -> CGRect {
        bodyRect(in: bounds, metrics: metrics)
    }

    /// Paste Stack 角标：贴内容区右上角（尺寸随编号宽度，不挤占正文布局）
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
    /// 图片来源区（缩略图 / 图片占位）
    case thumbnail
    /// 收藏星
    case star
    /// Paste Stack 角标
    case badge
    /// 底部 meta 行
    case meta
    /// 正文区（文本卡）
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
/// 语义与改造前的视图树一致：星标 / 角标 / 正文 / meta 都是**整卡的一部分**，
/// 所有区域的主键单击都选中、双击都粘贴、右键都弹菜单（没有各自的独立动作）。
/// 区域本身仍要区分：读屏焦点框、缩略图占位、以及将来给这些区域单独挂动作时都靠它。
public enum ClipboardCardHitTest {

    /// 点所在的区域
    ///
    /// - Parameters:
    ///   - point: 卡片内坐标（flipped）
    ///   - shortcutWidth: ⌘N 提示的实测宽度（不显示时 0）
    ///   - badgeSize: 角标实测尺寸（不显示时 .zero）
    ///   - isImage: 是否为图片条目（决定正文区是 .thumbnail 还是 .body）
    public static func region(at point: CGPoint, in bounds: CGRect,
                              shortcutWidth: CGFloat = 0, badgeSize: CGSize = .zero,
                              isImage: Bool, metrics: ClipboardCardGeometry.Metrics = .standard)
    -> ClipboardCardHitRegion {
        guard bounds.contains(point) else { return .body }
        // 星标 / 角标压在正文与 meta 之上：按优先级查表（顺序即优先级，空矩形不参与命中）
        let star = ClipboardCardGeometry.starRect(in: bounds, shortcutWidth: shortcutWidth, metrics: metrics)
        let badge = badgeSize.width > 0 && badgeSize.height > 0
            ? ClipboardCardGeometry.badgeRect(in: bounds, badgeSize: badgeSize, metrics: metrics) : .zero
        if let index = DrawnHitRegions.priorityIndex(at: point, in: [star, badge]) {
            return index == 0 ? .star : .badge
        }
        if point.y >= ClipboardCardGeometry.metaRowY(in: bounds, metrics: metrics) {
            return .meta
        }
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
