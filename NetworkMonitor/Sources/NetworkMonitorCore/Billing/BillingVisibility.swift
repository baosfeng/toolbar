import Foundation

// MARK: - 额度页可见性规则

/// 额度页可见性规则 — 「未配置凭据的 provider 不在额度页占位」的唯一判据
///
/// 用户明确要求「没有配置的需要隐藏」：额度页只展示**已启用且已配置凭据**的 provider。
/// 判据收敛在 Core 的纯函数里，而不是散在视图层，原因有两条：
/// - `MenuPanel` 由视觉改造任务独占，过滤写在视图里迟早被重写覆盖；
/// - 判据可被 TestRunner 直接断言（`NetworkMonitorCore` 是测试唯一依赖）。
///
/// 与之配套：`BillingProviderPreferences` 管「启用」，`BillingCredentialStore` 管
/// 「配置」，本规则只把两者合成一个布尔。设置页「额度 Provider」不读本规则 ——
/// 未配置的 provider 在设置页照旧显示「配置凭据…」，否则用户没有配置入口。
public enum BillingVisibilityRule {

    /// 单个 provider 是否出现在额度页
    ///
    /// - Parameters:
    ///   - isConfigured: 该 provider 是否已有可用凭据（存储或环境变量回退）
    ///   - isEnabled: 该 provider 的启用开关（停用 = 不查询、不出现在额度页）
    /// - Returns: 两项都为真才可见
    public static func isVisibleInCredits(isConfigured: Bool, isEnabled: Bool) -> Bool {
        isConfigured && isEnabled
    }

    /// 过滤出额度页要展示的条目（保持传入顺序）
    ///
    /// - Parameters:
    ///   - items: 待判定的条目序列
    ///   - isConfigured: 取条目的配置态
    ///   - isEnabled: 取条目的启用态
    /// - Returns: 仅可见条目，顺序与输入一致
    public static func visibleEntries<T>(_ items: [T],
                                         isConfigured: (T) -> Bool,
                                         isEnabled: (T) -> Bool) -> [T] {
        items.filter { isVisibleInCredits(isConfigured: isConfigured($0), isEnabled: isEnabled($0)) }
    }

    /// 是否整页空态：一个可见 provider 都没有
    ///
    /// 空态与「注册表为空」共用同一个视图（给一句说明 + 一个「去设置配置」入口），
    /// 否则全部未配置时额度页会是一片空白，用户找不到配置入口。
    public static func isEmptyState(visibleCount: Int) -> Bool { visibleCount == 0 }
}
