import Foundation

// MARK: - 额度提醒偏好

/// 额度提醒开关 —— 三类通知各自独立，默认都开
///
/// 只用一份实现（设置页与 `BillingAlertService` 都读它），避免两处默认值分叉：
/// - 阈值提醒：剩余跌破 5% / 4% / 3% / 2% / 1%；
/// - 窗口重置：会话 / 周 / 月额度进入新周期（用户明确要求「周额度重置要能通知」）；
/// - 余额回升：相邻两次观测剩余回升达到阈值（默认 10 个百分点）。
public struct BillingAlertPreferences {

    /// 阈值提醒开关键（缺省视为开启）
    public static let enabledKey = "billing.alerts.enabled"
    /// 窗口重置通知开关键（缺省开启）
    public static let resetEnabledKey = "billing.alerts.reset.enabled"
    /// 余额回升通知开关键（缺省开启）
    public static let recoveryEnabledKey = "billing.alerts.recovery.enabled"
    /// 回升阈值键（单位：百分点；缺省 10）
    public static let recoveryMinimumKey = "billing.alerts.recovery.minPercent"

    /// 回升阈值默认值与可用区间
    public static let defaultRecoveryMinimumPercent: Double = 10
    public static let recoveryMinimumRange: ClosedRange<Double> = 1...50
    /// 回升通知冷却（秒）：同一次回升不重复提醒
    public static let recoveryCooldown: TimeInterval = 3_600

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 是否发送阈值提醒（未写过该键时默认开启）
    public var isEnabled: Bool { boolValue(forKey: Self.enabledKey, defaultValue: true) }

    /// 是否发送「窗口已重置」通知
    public var isResetNotificationEnabled: Bool {
        boolValue(forKey: Self.resetEnabledKey, defaultValue: true)
    }

    /// 是否发送「额度已回升」通知
    public var isRecoveryNotificationEnabled: Bool {
        boolValue(forKey: Self.recoveryEnabledKey, defaultValue: true)
    }

    /// 回升阈值（百分点，钳制到 1…50）
    public var recoveryMinimumPercent: Double {
        guard storage.object(forKey: Self.recoveryMinimumKey) != nil else {
            return Self.defaultRecoveryMinimumPercent
        }
        return Self.clampMinimum(storage.double(forKey: Self.recoveryMinimumKey))
    }

    public func setEnabled(_ enabled: Bool) { storage.set(enabled, forKey: Self.enabledKey) }

    public func setResetNotificationEnabled(_ enabled: Bool) {
        storage.set(enabled, forKey: Self.resetEnabledKey)
    }

    public func setRecoveryNotificationEnabled(_ enabled: Bool) {
        storage.set(enabled, forKey: Self.recoveryEnabledKey)
    }

    public func setRecoveryMinimumPercent(_ percent: Double) {
        storage.set(Self.clampMinimum(percent), forKey: Self.recoveryMinimumKey)
    }

    /// 组装评估器选项（评估器本身不认识偏好类型）
    public var options: BillingAlertOptions {
        BillingAlertOptions(notifyThresholds: isEnabled,
                            notifyWindowReset: isResetNotificationEnabled,
                            notifyRecovery: isRecoveryNotificationEnabled,
                            recoveryMinimumPercent: recoveryMinimumPercent,
                            recoveryCooldown: Self.recoveryCooldown)
    }

    /// 阈值钳制（纯函数，供设置页与测试共用）
    public static func clampMinimum(_ percent: Double) -> Double {
        guard percent.isFinite else { return defaultRecoveryMinimumPercent }
        return min(max(percent, recoveryMinimumRange.lowerBound), recoveryMinimumRange.upperBound)
    }

    private func boolValue(forKey key: String, defaultValue: Bool) -> Bool {
        // bool(forKey:) 在键不存在时返回 false，必须先用 object 判存在才能表达「默认开」
        guard storage.object(forKey: key) != nil else { return defaultValue }
        return storage.bool(forKey: key)
    }
}
