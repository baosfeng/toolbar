import Foundation

// MARK: - 额度提醒偏好

/// 额度阈值提醒开关（5% / 4% / 3% / 2% / 1% 跌破时是否发系统通知）
///
/// 默认开启：提醒是额度监控的核心价值，用户明确关掉才不打扰。
/// 只用一份实现（设置页开关与 `BillingAlertService` 都读它），避免两处默认值分叉。
public struct BillingAlertPreferences {

    /// 存储键（缺省视为开启）
    public static let enabledKey = "billing.alerts.enabled"

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 是否发送额度提醒（未写过该键时默认开启）
    public var isEnabled: Bool {
        // bool(forKey:) 在键不存在时返回 false，必须先用 object 判存在才能表达「默认开」
        guard storage.object(forKey: Self.enabledKey) != nil else { return true }
        return storage.bool(forKey: Self.enabledKey)
    }

    /// 写入开关
    public func setEnabled(_ enabled: Bool) {
        storage.set(enabled, forKey: Self.enabledKey)
    }
}
