import Foundation

// MARK: - 额度 provider 可用性规则

/// 可用性规则 — 「没有凭据时开关置灰不可开」的唯一判据
///
/// 用户口径：「额度的 provider 应该默认都是关闭的，配置了之后才能打开」。
/// 后半句是**因果**，不只是顺序：必须先有凭据，开关才允许打开。把判据写成纯函数，
/// 视图只负责把 `canEnable == false` 翻译成置灰 + 一行「先填凭据」的说明，
/// 避免「设置页判断一套、面板判断另一套」。
///
/// 两种输入各司其职：
/// - `hasCredential`：凭据存储的解析结果（存储或环境变量回退），决定**能否打开**；
/// - `isEnabled`：启用偏好（缺键为 false），决定**当前是不是开着**。
///
/// 注意 `canEnable` 与可见性（`BillingVisibilityRule`）不是同一件事：
/// 凭据被清掉时启用键可能仍是 true，此时开关显示为开但不可操作；
/// 面板侧因为「未配置」本来就不会展示它，两边不会打架。
public enum BillingProviderAvailability {

    /// 开关是否可操作（无凭据时不可开）
    ///
    /// - Parameters:
    ///   - hasCredential: 该实例是否已有可用凭据
    ///   - isEnabled: 该实例当前是否处于启用态
    /// - Returns: 无凭据一律 false；有凭据时恒 true（已开着的允许关，未开的允许开）
    public static func canEnable(hasCredential: Bool, isEnabled: Bool) -> Bool {
        hasCredential
    }

    /// 行内说明文案（开关不可用时给出「先填凭据」，可用时不给噪音）
    public static func disabledHint(hasCredential: Bool, isEnabled: Bool) -> String? {
        guard !canEnable(hasCredential: hasCredential, isEnabled: isEnabled) else { return nil }
        return "先填凭据，再打开开关"
    }

    /// 是否「已启用但凭据没了」—— 开关仍显示为开，但查询不会发生
    ///
    /// 这类实例在面板上不可见（`BillingVisibilityRule` 要求已配置），设置页据此
    /// 提示「已启用，等凭据」比直接把它画成关闭更贴近事实。
    public static func isEnabledWithoutCredential(hasCredential: Bool, isEnabled: Bool) -> Bool {
        isEnabled && !hasCredential
    }
}
