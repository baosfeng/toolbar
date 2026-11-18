import Foundation

// MARK: - 菜单面板分页目录（纯逻辑）

/// 菜单面板分页的稳定标识登记表 —— 纯值，供偏好层、迁移层与测试共用
///
/// 为什么单独放一份：分页枚举在 App 目标（TestRunner 看不到），而「偏好里存的是哪些 id、
/// 哪些 id 已经下线」是**可以单测的纯口径**。把它放在 UI 目标，测试能直接断言
/// 「已下线的 id 被安全忽略、其余分页顺序不动」，不必 import 可执行目标。
///
/// 顺序即声明顺序（= 默认顺序 = 数字键顺序）。
public enum PanelTabCatalog {

    /// 当前在用的全部分页 id（顺序即默认顺序）
    public static let stableIDs = ["network", "transfer", "credits", "token", "system"]

    /// 已下线分页的 id —— 老用户的偏好里可能还留着这些串
    ///
    /// 「剪贴板」分页下线：历史剪贴板只在屏幕底部的独立浮层面板展示，
    /// 菜单面板不再重复一份（用户口径：「默认的历史剪贴板不需要显示在详情 tab」）。
    /// 这些 id 不在 `stableIDs` 里，读偏好时由 `SettingsOrderCoding.normalize` 丢弃，
    /// 不需要额外的清理迁移。
    public static let retiredIDs = ["clipboard"]

    /// 旧版 Int rawValue → 稳定 id 的**冻结映射**
    ///
    /// 不能按当前枚举的 rawValue 现推：rawValue 是声明位置，删掉一个 case 会让后面的
    /// 编号整体前移（旧数据里的 2 本来是 transfer，现推会读成 credits），
    /// 于是「顺序错位」且没有任何编译错误。这张表记录的是**历史上写出去过的编号**。
    public static let legacyRawValueToStableID: [Int: String] = [
        0: "network",
        1: "clipboard",   // 已下线：迁移后仍会被 normalize 丢弃
        2: "transfer",
        3: "credits",
        4: "token",
        5: "system",
    ]

    /// 当前全部合法 id（= stableIDs，语义别名，便于调用点自述）
    public static var knownIDs: [String] { stableIDs }
}
