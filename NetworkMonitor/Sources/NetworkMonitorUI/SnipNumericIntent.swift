import Foundation

// MARK: - 修饰键 → 调整意图

/// 同一条调整通路（滚轮 / 按键）配上修饰键后的语义
///
/// 为什么要有这一层：`⇧` 与 `⌥` 到底该「变快」还是「变慢」，业界没有共识 ——
/// Photoshop 官方文档说 ⇧ 拖是加速 10 倍，而社区教程里同一套说明被理解成"精细微调"，
/// 两种说法长期并存。所以这个语义**不能靠约定俗成**，必须在本项目里写死一处、
/// 并在操作提示里写明。这个枚举就是那一处。
///
/// 映射（全覆盖层唯一）：
/// - 无修饰键 / ⇧ → `coarse`（⇧ 在原有语义里已被"缩边"等占用，这里不抢）
/// - ⌥ → `fine`（半档微调）
/// - ⌘ → `fast`（×8 粗调）
///
/// 之所以不用 ⇧ 做 fast：覆盖层里 ⇧ 已经承载三种语义（锁比例、约束形状、放大镜切色格式），
/// 再加第四种会让「按住 ⇧ 到底会发生什么」彻底说不清。⌘ 在数值调整语境下没有别的用途。
public enum SnipNumericIntent: Equatable, Sendable {

    /// 一个最小单位（滚轮一格 / 按一次键）
    case coarse
    /// 半档（= `quantum`）—— 比最小单位更细
    case fine
    /// ×`fastMultiplier` 个最小单位 —— 长距离快速移动
    case fast

    /// 快调倍率
    public static let fastMultiplier: CGFloat = 8

    /// 精调的步长比例（相对于最小单位）
    public static let fineRatio: CGFloat = 0.5

    /// 由修饰键判定意图
    ///
    /// 优先级：⌘ > ⌥（两者同按时按快调处理——用户按住 ⌘ 的意图是"快点走完"，
    /// 若被 ⌥ 降级成半步会与预期相反）。
    ///
    /// 注意这里**不读 ⇧**：⇧ 在覆盖层已有三种语义，再给它一个会让修饰键矩阵失控。
    /// 调用方若要区分 ⇧，必须在上层显式判掉，不能指望这个函数。
    public static func resolve(command: Bool, option: Bool) -> SnipNumericIntent {
        if command { return .fast }
        if option { return .fine }
        return .coarse
    }

    /// HUD 上的角标文案（让用户当场知道自己在粗调还是精调）
    public var badge: String? {
        switch self {
        case .coarse: return nil
        case .fine: return "精调"
        case .fast: return "快调"
        }
    }
}
