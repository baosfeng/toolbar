import Foundation

// MARK: - 计费刷新节流（纯逻辑）

/// 刷新节流判定 — 每个 provider 独立计时，有效间隔取「全局下限」与「provider 建议间隔」的较大值
///
/// 抽成纯函数的原因：状态管理器是 MainActor 隔离的，而节流规则与 UI / 并发无关，
/// 独立出来可直接用断言覆盖边界（首次刷新、未到期、provider 长间隔、强制刷新），
/// 也让「某个 provider 少打接口」这条口径只有一个实现点。
public enum BillingRefreshScheduler {

    /// 全局刷新下限（秒）— 任何 provider 都不会比它更频繁
    ///
    /// Ollama 限流 10 次/分钟/用户（跨设备共享），60 秒留出余量。
    public static let minimumInterval: TimeInterval = 60

    /// 某 provider 的有效刷新间隔
    ///
    /// - Parameter providerMinimum: provider 建议的最小间隔（0 = 未声明）
    /// - Returns: 不小于全局下限的间隔
    public static func interval(providerMinimum: TimeInterval) -> TimeInterval {
        max(minimumInterval, providerMinimum)
    }

    /// 本次是否该发起刷新
    ///
    /// - Parameters:
    ///   - now: 当前时刻
    ///   - lastAttempt: 上次发起刷新的时刻（nil = 从未刷新）
    ///   - providerMinimum: provider 建议的最小间隔（0 = 未声明）
    ///   - force: 强制刷新（打开面板 / 保存凭据时跳过全部节流）
    public static func isDue(now: Date, lastAttempt: Date?,
                             providerMinimum: TimeInterval, force: Bool) -> Bool {
        if force { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval(providerMinimum: providerMinimum)
    }
}
