import Foundation

// MARK: - 额度卡片状态胶囊判据（纯逻辑，可单测）

/// 状态胶囊的四档语义
public enum BillingStatusKind: Equatable, Sendable {
    /// 正常（有数据且无错误）
    case ok
    /// 已限流 / 额度告警（任一窗口剩余低于阈值）
    case warn
    /// 请求失败
    case error
    /// 查询中
    case loading
    /// 尚无数据（从未成功刷新过）
    case idle
}

/// 状态胶囊判据 —— 卡片右上角那颗胶囊的文案与语义色
///
/// 存在理由（用户现场反馈「额度没用了」）：此前判据只覆盖 出错 / 限流 / 查询中，
/// 其余一律落到 else 显示「正常」。于是一个**从未拿到过任何数据**的 provider
/// （余额 nil、从未刷新过）也会顶着绿色的「正常」，用户看到的是「正常 + —」，
/// 完全无法判断到底哪一环坏了。这里补第 4 档「未刷新」，把「没数据」显式说出来。
public enum BillingProviderStatusLogic {

    /// 告警阈值：任一窗口剩余低于该比例即判「限流」
    public static let warnThreshold: Double = 0.2

    /// 判定胶囊
    ///
    /// 优先级：出错 > 限流 > 查询中 > 未刷新 > 正常。
    /// 「未刷新」放在「查询中」之后：正在查的时候别催用户。
    ///
    /// - Parameters:
    ///   - errorMessage: 失败文案（nil = 本次无错误）
    ///   - worstRemaining: 各窗口里最低的剩余比例（nil = 没有百分比窗口）
    ///   - isLoading: 是否正在请求
    ///   - hasBalance: 是否已有成功拿到的余额数据
    public static func kind(errorMessage: String?,
                            worstRemaining: Double?,
                            isLoading: Bool,
                            hasBalance: Bool) -> BillingStatusKind {
        if errorMessage != nil { return .error }
        if let worstRemaining, worstRemaining < warnThreshold { return .warn }
        if isLoading { return .loading }
        // 没有余额数据（含「provider 只返回空余额」）→ 未刷新，而不是「正常」
        return hasBalance ? .ok : .idle
    }

    /// 胶囊文案
    public static func text(_ kind: BillingStatusKind) -> String {
        switch kind {
        case .ok: return "正常"
        case .warn: return "限流"
        case .error: return "出错"
        case .loading: return "查询中"
        case .idle: return "未刷新"
        }
    }

    /// 便捷重载：直接吃「余额是否有内容」与窗口剩余
    public static func kind(errorMessage: String?,
                            remainingFractions: [Double],
                            isLoading: Bool,
                            hasBalance: Bool) -> BillingStatusKind {
        kind(errorMessage: errorMessage,
             worstRemaining: remainingFractions.min(),
             isLoading: isLoading,
             hasBalance: hasBalance)
    }
}
