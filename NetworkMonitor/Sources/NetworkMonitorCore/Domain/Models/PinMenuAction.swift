import Foundation

// MARK: - 贴图右键菜单分组

/// 贴图右键菜单的语义分组 —— 只决定「在哪里画分隔线」，不再限制排序
///
/// 分组曾经是排序边界（危险组恒在末尾、组内才能换序），现已全部放开：
/// 九项按用户偏好的顺序排列，分隔线按最终顺序在**语义分组变化处**自动插入。
/// 于是跨组换序也连贯：把「缩略图」挪到第一位，它前面不再有分隔线，
/// 后面接回「另存为」时按分组变化补一条，菜单读起来仍是一段一段的。
///
/// 危险项不再靠位置兜底，改为视觉兜底（菜单里红色文字）——
/// 位置由用户决定，误点风险由颜色提醒承担。
public enum PinMenuActionGroup: String, CaseIterable, Equatable, Sendable, Hashable {
    /// 复制与另存为
    case output
    /// 旋转 / 镜像 / 缩略图等变换
    case transform
    /// 重置大小与不透明度
    case reset
    /// 关闭与销毁（危险组）
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
}

// MARK: - 贴图右键菜单项

/// 贴图窗口右键菜单的九项 —— 标题、分组与默认顺序的唯一真源
///
/// 菜单装配（`PinWindow.rightMouseDown`）与设置页可排序卡片共用这一份定义：
/// 标题不再散落在拼接代码里，测试也能直接断言顺序，不必起窗口。
///
/// 排序口径（用户要求「贴图菜单全部放开可调」）：
/// - 九项整列自由换序，跨组也可以（设置页上移 / 下移不再有灰化行）；
/// - 分隔线按最终顺序在语义分组变化处自动插入（`PinMenuDivider`），不看声明顺序；
/// - 危险项（`isDestructive`）位置由顺序键决定，不再恒在末尾，
///   误点风险改由视觉承担：菜单里用红色文字标出。
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

    /// 所属语义分组（只决定分隔线位置，不参与排序限制）
    public var group: PinMenuActionGroup {
        switch self {
        case .copy, .save: return .output
        case .rotate, .mirrorHorizontal, .mirrorVertical, .thumbnail: return .transform
        case .resetSizeAndAlpha: return .reset
        case .close, .destroy: return .dismiss
        }
    }

    /// 是否是危险动作（不可恢复 / 破坏性）—— 菜单里据此标红
    public var isDestructive: Bool { group == .dismiss }

    /// 默认顺序 —— 与声明顺序一致，也就是硬编码菜单时期的顺序
    ///
    /// 偏好里没有顺序键（老配置）时按它回落：升级不改变任何人的菜单外观。
    public static let defaultOrder: [PinMenuAction] = allCases

    /// 某一组的默认组内顺序
    public static func defaultOrder(in group: PinMenuActionGroup) -> [PinMenuAction] {
        defaultOrder.filter { $0.group == group }
    }
}

// MARK: - 分隔线落位

/// 右键菜单分隔线的落位规则（纯函数，可单测）
///
/// 规则：第一项之前不画；此后**每当语义分组与上一项不同**就在该项之前画一条。
/// 之所以按「最终顺序」而不是「固定分组区间」算：九项已允许跨组换序，
/// 按固定区间画会在乱序时出现空段（连续两条分隔线）或该断的地方没断。
public enum PinMenuDivider {

    /// 每项之前是否需要一条分隔线（与入参等长）
    public static func leadingSeparators(for order: [PinMenuAction]) -> [Bool] {
        var result: [Bool] = []
        result.reserveCapacity(order.count)
        var previous: PinMenuActionGroup?
        for action in order {
            result.append(previous != nil && previous != action.group)
            previous = action.group
        }
        return result
    }
}
