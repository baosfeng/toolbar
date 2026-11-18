import Foundation

// MARK: - 窗口种类清单

/// 窗口种类清单 — 设置页「恢复通知按窗口勾选」要列哪些窗口的唯一判据
///
/// 用户口径：「只列该 provider 实际出现过的窗口种类；拿不到就列它声明的种类」。
/// 判据放 Core 是为了两件事：老配置升级后 UI 不会凭空多出没意义的勾选项，
/// 以及「观测 → 声明 → 兜底」这条回落顺序能被 TestRunner 直接断言。
public enum BillingWindowKindInventory {

    /// 兜底种类：既没有观测数据、provider 也没声明时列这四档
    ///
    /// 不含 `custom`：自定义窗口没有稳定标题，勾选后用户也认不出是哪一份额度。
    public static let fallbackKinds: [BillingWindowKind] = [.session, .daily, .weekly, .monthly]

    /// 从余额快照里提取实际出现过的窗口种类（去重保序）
    ///
    /// - Parameter balance: 最近一次成功查询的余额（nil = 尚未取到数据）
    /// - Returns: 出现过的种类；`window == nil` 的额度不贡献种类
    ///
    /// 内含额度（`included`）按月度窗口计入：它的计费周期就是一个自然月，
    /// 与服务端给的 `period.end` 一一对应。
    public static func observed(in balance: BillingBalance?) -> [BillingWindowKind] {
        guard let balance else { return [] }
        var kinds: [BillingWindowKind] = []
        if balance.included?.period != nil, !kinds.contains(.monthly) { kinds.append(.monthly) }
        for kind in balance.percentLimits.compactMap({ $0.window?.kind }) where !kinds.contains(kind) {
            kinds.append(kind)
        }
        return kinds
    }

    /// 最终要列给用户的种类
    ///
    /// 回落顺序：实际观测 → provider 声明 → 四档兜底。观测优先的原因：
    /// Claude 可能同时有 5 小时与多条「每周」，而 Ollama 只有月度与周度，
    /// 声明只能给「可能有哪些」，实际观测才是「这家现在真的有哪几份」。
    ///
    /// - Parameters:
    ///   - observed: 实际出现过的种类
    ///   - declared: provider 声明的种类（未声明传空数组）
    /// - Returns: 列表非空，且不含 `custom`
    public static func options(observed: [BillingWindowKind],
                               declared: [BillingWindowKind]) -> [BillingWindowKind] {
        let filtered = dedupe(observed).filter { $0 != .custom }
        if !filtered.isEmpty { return filtered }
        let declaredKinds = dedupe(declared).filter { $0 != .custom }
        return declaredKinds.isEmpty ? fallbackKinds : declaredKinds
    }

    /// 单个 provider 的列表（观测优先，取不到时用声明）
    public static func options(balance: BillingBalance?,
                               declared: [BillingWindowKind]) -> [BillingWindowKind] {
        options(observed: observed(in: balance), declared: declared)
    }

    /// 去重并保持输入顺序
    public static func dedupe(_ kinds: [BillingWindowKind]) -> [BillingWindowKind] {
        var result: [BillingWindowKind] = []
        for kind in kinds where !result.contains(kind) { result.append(kind) }
        return result
    }
}
