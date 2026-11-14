import Foundation

// MARK: - 缩略图失败重试策略

/// 缩略图解码失败的退避与终态策略 — 纯状态机（无 AppKit / 无 Dispatch，时间可注入）
///
/// 背景：旧实现把解码失败的 hash 记进「本会话内不再重试」的黑名单，一个坏文件就让该哈希
/// 整个会话停在占位符号。现在失败只做**冷却 + 次数上限**：
/// 1. 冷却：同一哈希失败后 `cooldown`（默认 30s）内不再尝试，避免面板重绘时对一个坏文件空转；
/// 2. 终态：累计失败达 `maxAttempts`（默认 3）后不再重试，避免永久重试；
/// 3. 成功：`markSucceeded` 清空该哈希全部失败记录，之后可再次请求。
///
/// 「本会话内不再重试」的最终判定由本类型的 `shouldRetry` 唯一决定，
/// App 层的 `ClipboardThumbnailLoadGate` 只保留并发与在途去重两件事。
public struct ClipboardThumbnailRetryPolicy: Sendable {

    /// 默认冷却时长（秒）
    public static let defaultCooldown: TimeInterval = 30

    /// 默认最大尝试次数（含首次），达到后转终态
    public static let defaultMaxAttempts = 3

    /// 冷却时长（≥ 0；负数归一化为 0）
    public let cooldown: TimeInterval

    /// 最大失败次数（含首次；≤ 0 归一化为默认值）
    public let maxAttempts: Int

    /// 各哈希的失败记录（最近一次失败时间 + 累计次数）
    private var failures: [String: Failure] = [:]

    /// 单条失败记录
    private struct Failure {
        /// 最近一次失败时间
        var lastFailure: Date
        /// 累计失败次数
        var attempts: Int
    }

    public init(cooldown: TimeInterval = defaultCooldown, maxAttempts: Int = defaultMaxAttempts) {
        self.cooldown = cooldown > 0 ? cooldown : 0
        self.maxAttempts = maxAttempts > 0 ? maxAttempts : Self.defaultMaxAttempts
    }

    // MARK: 查询

    /// 该哈希累计失败次数（未失败过为 0）
    public func failureCount(hash: String) -> Int {
        failures[normalized(hash)]?.attempts ?? 0
    }

    /// 该哈希是否已进入终态（累计失败达上限，本会话内不再重试）
    public func isExhausted(hash: String) -> Bool {
        failureCount(hash: hash) >= maxAttempts
    }

    /// 是否允许重试
    ///
    /// 从未失败 → true；已达 `maxAttempts` → false（终态）；
    /// 冷却未过 → false；冷却已过 → true。
    /// - Parameters:
    ///   - hash: 内容哈希（空白哈希视为非法入参，一律 false）
    ///   - now: 当前时间（可注入，便于测试）
    public func shouldRetry(hash: String, now: Date = Date()) -> Bool {
        let key = normalized(hash)
        guard !key.isEmpty else { return false }
        guard let failure = failures[key] else { return true }
        guard failure.attempts < maxAttempts else { return false }
        return now.timeIntervalSince(failure.lastFailure) >= cooldown
    }

    /// 距离下次允许重试还剩多少秒
    ///
    /// 可立即重试（从未失败 / 冷却已过）返回 0；已进入终态返回 nil（调用方据此不再排期）。
    public func retryDelay(hash: String, now: Date = Date()) -> TimeInterval? {
        let key = normalized(hash)
        guard !key.isEmpty else { return nil }
        guard let failure = failures[key] else { return 0 }
        guard failure.attempts < maxAttempts else { return nil }
        let elapsed = now.timeIntervalSince(failure.lastFailure)
        return max(0, cooldown - elapsed)
    }

    // MARK: 状态变更

    /// 记录一次失败：累计次数 +1 并刷新时间戳；空白哈希无副作用
    public mutating func markFailed(hash: String, now: Date = Date()) {
        let key = normalized(hash)
        guard !key.isEmpty else { return }
        // 已达上限后不再累加，避免长时间运行后计数无意义地增长
        let attempts = failures[key]?.attempts ?? 0
        guard attempts < maxAttempts else { return }
        failures[key] = Failure(lastFailure: now, attempts: attempts + 1)
    }

    /// 记录一次成功：清空该哈希全部失败记录（之后可再次请求）
    public mutating func markSucceeded(hash: String) {
        let key = normalized(hash)
        guard !key.isEmpty else { return }
        failures.removeValue(forKey: key)
    }

    /// 清空全部记录（会话级重置 / 测试收尾）
    public mutating func reset() {
        failures.removeAll()
    }

    // MARK: 内部实现

    /// hash 归一化：去首尾空白（空白哈希视为非法入参）
    private func normalized(_ hash: String) -> String {
        hash.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
