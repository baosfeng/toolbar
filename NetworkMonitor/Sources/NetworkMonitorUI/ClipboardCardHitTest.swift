import CoreGraphics

// MARK: - 卡片命中测试（从 ClipboardCardGeometry 拆出，守住单文件 15 KiB 上限）

// 几何算「东西在哪」，这里算「点到的是哪一块、该做什么」：两者共用同一套几何口径，
// 但分属不同关注点，拆开后几何文件只留尺寸与矩形。
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
