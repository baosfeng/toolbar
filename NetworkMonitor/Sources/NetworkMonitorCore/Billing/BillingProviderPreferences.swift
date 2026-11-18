import Foundation

// MARK: - 额度 provider 启用偏好

/// 额度 provider 启用偏好 — 停用者不查询、不出现在额度页，凭据原样保留
///
/// **默认关闭**（未写过对应键）：用户口径是「provider 应该默认都是关闭的，配置了之后才能打开」，
/// 因此新装 / 新注册的 provider 只有用户显式打开才参与额度查询。
///
/// 老用户不被静默下线：只要键存在且为 true（用户此前显式开过），本实现原样返回 true，
/// 不会因为默认值翻转而把已使用的 provider 关掉；受影响面严格限定在「从未写过启用键」的实例。
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

    /// 是否启用（**未写过该键时默认关闭**）
    ///
    /// 键存在即为用户的选择，按原值返回；只有「从未写过启用键」才落到默认关闭。
    public func isEnabled(_ providerID: String) -> Bool {
        // bool(forKey:) 在键不存在时返回 false，必须先用 object 判存在才能区分
        // 「用户显式关掉」与「从来没有过选择」——两者对 UI 的提示文案不同。
        guard hasExplicitChoice(providerID) else { return false }
        return storage.bool(forKey: Self.storageKey(for: providerID))
    }

    /// 该 provider 是否被用户显式设置过启用开关
    ///
    /// 设置页据此区分「默认关闭（还没配过）」与「用户主动关掉」；也是默认值翻转后
    /// 判断「这个实例会不会受到影响」的唯一判据。
    public func hasExplicitChoice(_ providerID: String) -> Bool {
        storage.object(forKey: Self.storageKey(for: providerID)) != nil
    }

    /// 写入启用开关
    public func setEnabled(_ enabled: Bool, for providerID: String) {
        storage.set(enabled, forKey: Self.storageKey(for: providerID))
    }

    /// 清除启用键（删除实例时调用；重建同名实例时回到「默认关闭」）
    public func removeEnabled(for providerID: String) {
        storage.removeObject(forKey: Self.storageKey(for: providerID))
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
