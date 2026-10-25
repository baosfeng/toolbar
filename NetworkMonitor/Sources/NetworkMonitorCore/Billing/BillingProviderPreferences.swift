import Foundation

// MARK: - 额度 provider 启用偏好

/// 额度 provider 启用偏好 — 停用者不查询、不出现在额度页，凭据原样保留
///
/// 默认启用（未写过对应键）：新装 / 新注册的 provider 立刻参与额度查询，
/// 用户明确关掉才隐藏。设置页开关与 `BillingMonitor` 只读这一份实现，避免两处默认值分叉。
///
/// 存储键：`billing.enabled.<providerID>`（与凭据键 `billing.credential.<providerID>` 分开，
/// 关闭开关不会删除凭据，重新打开即可继续查询）。
public struct BillingProviderPreferences {

    /// 存储键前缀（完整键：`billing.enabled.<providerID>`）
    public static let keyPrefix = "billing.enabled."

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 指定 provider 的偏好存储键
    public static func storageKey(for providerID: String) -> String {
        keyPrefix + providerID
    }

    /// 是否启用（未写过该键时默认启用）
    public func isEnabled(_ providerID: String) -> Bool {
        // bool(forKey:) 在键不存在时返回 false，必须先用 object 判存在才能表达「默认开」
        guard storage.object(forKey: Self.storageKey(for: providerID)) != nil else { return true }
        return storage.bool(forKey: Self.storageKey(for: providerID))
    }

    /// 写入启用开关
    public func setEnabled(_ enabled: Bool, for providerID: String) {
        storage.set(enabled, forKey: Self.storageKey(for: providerID))
    }

    /// 按偏好过滤 provider id（保持传入顺序）
    public func enabledIDs(from providerIDs: [String]) -> [String] {
        Self.filterEnabled(providerIDs, preferences: self)
    }

    /// 纯函数过滤 — 供状态管理器重建列表与测试直接断言
    ///
    /// - Parameters:
    ///   - providerIDs: 注册表中的全部 provider id（保持注册顺序）
    ///   - preferences: 启用偏好
    /// - Returns: 仅启用的 id，顺序与输入一致
    public static func filterEnabled(_ providerIDs: [String],
                                     preferences: BillingProviderPreferences) -> [String] {
        providerIDs.filter { preferences.isEnabled($0) }
    }
}
