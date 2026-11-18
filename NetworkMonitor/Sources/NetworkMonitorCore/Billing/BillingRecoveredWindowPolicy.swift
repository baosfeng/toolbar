import Foundation

// MARK: - 额度提醒偏好（按窗口细分恢复通知）

/// 恢复通知的窗口白名单 —— 纯值，评估器与设置页共用同一份规则
///
/// 语义（用户口径「有的是周额度和五小时额度，可以自定义恢复通知」）：
/// - `enabledKinds == nil`：**没有任何窗口键**，回落既有行为 —— 所有窗口都通知；
/// - `enabledKinds == []`：用户把所有窗口都关了（显式选择），一条都不通知；
/// - 其余：只通知集合内的窗口种类。
///
/// 存储键按 `billing.alerts.recovered.<providerID>.<windowKind>` 逐窗口展开：
/// 缺某个键 = 该窗口默认通知，因此老配置不需要任何迁移。
public struct BillingRecoveredWindowPolicy: Sendable, Equatable {

    /// 参与配置的 provider（实例标识）
    public let providerID: String
    /// 允许通知的窗口种类（nil = 未做任何窗口选择，全部通知）
    public let enabledKinds: Set<BillingWindowKind>?

    public init(providerID: String, enabledKinds: Set<BillingWindowKind>?) {
        self.providerID = providerID
        self.enabledKinds = enabledKinds
    }

    /// 未配置任何窗口的 policy（全窗口通知）
    public static func unrestricted(providerID: String) -> BillingRecoveredWindowPolicy {
        BillingRecoveredWindowPolicy(providerID: providerID, enabledKinds: nil)
    }

    /// 该窗口的种类是否允许发恢复通知
    ///
    /// - Parameter kind: 额度窗口种类；**nil（无窗口信息）一律放行**
    ///
    /// `nil` 放行是硬要求：纯余额型 provider（DeepSeek / OpenRouter / Moonshot）
    /// 的额度没有窗口概念，若按「不在白名单」处理，新开关会把它们静默掉。
    public func allows(_ kind: BillingWindowKind?) -> Bool {
        guard let kind else { return true }
        guard let enabledKinds else { return true }
        return enabledKinds.contains(kind)
    }
}

// MARK: - 偏好读写

extension BillingAlertPreferences {

    /// 窗口恢复通知键前缀（完整键：`billing.alerts.recovered.<providerID>.<windowKind>`）
    public static let recoveredWindowKeyPrefix = "billing.alerts.recovered."

    /// 指定 provider + 窗口的存储键
    public static func recoveredWindowKey(providerID: String,
                                          windowKind: BillingWindowKind) -> String {
        recoveredWindowKeyPrefix + providerID + "." + windowKind.rawValue
    }

    /// 该 provider 是否被配置过任意窗口（决定回落「全通知」还是按勾选）
    public func hasRecoveredWindowSelection(providerID: String) -> Bool {
        BillingWindowKind.allCases.contains { kind in
            storage.object(forKey: Self.recoveredWindowKey(providerID: providerID,
                                                            windowKind: kind)) != nil
        }
    }

    /// 单个窗口是否通知恢复（缺键默认 true）
    public func isRecoveredWindowEnabled(providerID: String, windowKind: BillingWindowKind) -> Bool {
        let key = Self.recoveredWindowKey(providerID: providerID, windowKind: windowKind)
        guard storage.object(forKey: key) != nil else { return true }
        return storage.bool(forKey: key)
    }

    /// 写入单个窗口的恢复通知开关
    public func setRecoveredWindowEnabled(_ enabled: Bool, providerID: String,
                                          windowKind: BillingWindowKind) {
        storage.set(enabled, forKey: Self.recoveredWindowKey(providerID: providerID,
                                                              windowKind: windowKind))
    }

    /// 清除该 provider 的全部窗口键（删除实例时调用，回到「全通知」默认）
    public func removeRecoveredWindowSelection(providerID: String) {
        for kind in BillingWindowKind.allCases {
            storage.removeObject(forKey: Self.recoveredWindowKey(providerID: providerID,
                                                                 windowKind: kind))
        }
    }

    /// 该 provider 的窗口白名单（nil = 未配置过任何窗口，回落全通知）
    ///
    /// 只遍历 `BillingWindowKind` 里存在的种类：历史脏键读不出来，
    /// 因此既不会崩，也不会被误当成「用户勾过」。
    public func recoveredWindowPolicy(for providerID: String) -> BillingRecoveredWindowPolicy {
        guard hasRecoveredWindowSelection(providerID: providerID) else {
            return .unrestricted(providerID: providerID)
        }
        let enabled = BillingWindowKind.allCases.filter {
            isRecoveredWindowEnabled(providerID: providerID, windowKind: $0)
        }
        return BillingRecoveredWindowPolicy(providerID: providerID, enabledKinds: Set(enabled))
    }

    /// 是否该为该 provider / 窗口发恢复通知 —— 评估器与设置页共用的唯一判据
    ///
    /// - Parameter windowKind: 额度窗口种类；nil（无窗口信息）恒为 true
    public func shouldNotifyRecovery(providerID: String, windowKind: BillingWindowKind?) -> Bool {
        recoveredWindowPolicy(for: providerID).allows(windowKind)
    }

    /// 组装某个 provider 的评估选项（窗口白名单随 provider 走）
    ///
    /// 与 `options` 的差别只有恢复窗口策略：`options` 不知道 providerID，
    /// 因此凡是要发恢复通知的调用点都必须用本方法。
    public func options(for providerID: String) -> BillingAlertOptions {
        var result = options
        result.recoveredWindows = recoveredWindowPolicy(for: providerID)
        return result
    }
}
