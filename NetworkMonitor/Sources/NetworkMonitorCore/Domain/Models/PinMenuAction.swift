import Foundation

// MARK: - 贴图右键菜单分组

/// 贴图右键菜单的分组 —— 分组顺序固定，用户排序只在组内做
///
/// 分组不是装饰：菜单里组与组之间画分隔线，且「关闭与销毁」这一组恒在最后 ——
/// 危险动作不会被排到菜单上半部分，更不会被误点。因此组顺序写成常量，不参与用户排序。
public enum PinMenuActionGroup: String, CaseIterable, Equatable, Sendable, Hashable {
    /// 复制与另存为
    case output
    /// 旋转 / 镜像 / 缩略图等变换
    case transform
    /// 重置大小与不透明度
    case reset
    /// 关闭与销毁（危险组，恒在最后）
    case dismiss

    /// 设置页行副标题里用的分组名
    public var title: String {
        switch self {
        case .output: return "复制与另存为"
        case .transform: return "变换"
        case .reset: return "重置"
        case .dismiss: return "关闭与销毁"
        }
    }

    /// 组内是否允许用户换序
    ///
    /// 危险组不允许：组内「关闭（可恢复）」必须排在「销毁」之前，
    /// 手一滑把「销毁」换到上面，右键菜单就变成了误删入口。
    public var isSortable: Bool { self != .dismiss }
}

// MARK: - 贴图右键菜单项

/// 贴图窗口右键菜单的九项 —— 标题、分组与默认顺序的唯一真源
///
/// 菜单装配（`PinWindow.rightMouseDown`）与设置页可排序卡片共用这一份定义：
/// 标题不再散落在拼接代码里，测试也能直接断言顺序，不必起窗口。
///
/// 排序口径：
/// - 组顺序固定为 `groupOrder`（复制与另存为 → 变换 → 重置 → 关闭与销毁）；
/// - 用户只能在组内换序（`PinMenuActionGroup.isSortable`）；
/// - 因此「销毁」永远在最后，且「关闭（可恢复）」永远在它前面 —— 这是枚举里的常量，不靠装配顺序偶然成立。
public enum PinMenuAction: String, CaseIterable, Equatable, Sendable, Hashable {
    /// 复制图像到剪贴板
    case copy
    /// 另存为文件
    case save
    /// 顺时针旋转 90°
    case rotate
    /// 水平镜像
    case mirrorHorizontal
    /// 垂直镜像
    case mirrorVertical
    /// 固定尺寸缩略图
    case thumbnail
    /// 重置为 100% 大小与 100% 不透明
    case resetSizeAndAlpha
    /// 关闭（可恢复）
    case close
    /// 销毁（不可恢复）
    case destroy

    /// 菜单标题 —— 与硬编码菜单时期的文案逐字一致，老用户看不到变化
    public var title: String {
        switch self {
        case .copy: return "复制图像"
        case .save: return "另存为…"
        case .rotate: return "旋转 90°"
        case .mirrorHorizontal: return "水平镜像"
        case .mirrorVertical: return "垂直镜像"
        case .thumbnail: return "缩略图"
        case .resetSizeAndAlpha: return "重置大小与不透明度"
        case .close: return "关闭（可恢复）"
        case .destroy: return "销毁"
        }
    }

    /// 所属分组（决定分隔线与可排序范围）
    public var group: PinMenuActionGroup {
        switch self {
        case .copy, .save: return .output
        case .rotate, .mirrorHorizontal, .mirrorVertical, .thumbnail: return .transform
        case .resetSizeAndAlpha: return .reset
        case .close, .destroy: return .dismiss
        }
    }

    /// 是否是危险动作（不可恢复 / 破坏性）
    public var isDestructive: Bool { group == .dismiss }

    /// 默认顺序 —— 与声明顺序一致，也就是硬编码菜单时期的顺序
    ///
    /// 偏好里没有顺序键（老配置）时按它回落：升级不改变任何人的菜单外观。
    public static let defaultOrder: [PinMenuAction] = allCases

    /// 固定组顺序 —— 危险组恒在最后，不参与用户排序
    public static let groupOrder: [PinMenuActionGroup] = [.output, .transform, .reset, .dismiss]

    /// 某一组的默认组内顺序
    public static func defaultOrder(in group: PinMenuActionGroup) -> [PinMenuAction] {
        defaultOrder.filter { $0.group == group }
    }
}
