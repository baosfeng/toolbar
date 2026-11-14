import Foundation

// MARK: - 串行队列（自带排队等待计时）

/// 串行队列包装 — 所有 sqlite3 调用经它的 `sync` 执行
///
/// 排队等待超过阈值时记一条（等待时长 + 执行时长 + 调用方函数名）：面板「未响应」的现场是
/// **主线程排在数据库队列后面**，这条日志能直接指认「谁在排队、排了多久、真正执行了多久」，
/// 不必再靠 sample 事后反推（见 2026-11 事故复盘：生产日志为零，只能猜）。
public struct DatabaseQueue: @unchecked Sendable {

    /// 排队等待告警阈值（毫秒）：超过即记一条
    public static let slowWaitThresholdMs: Double = 200

    private let queue: DispatchQueue
    private let thresholdMs: Double
    private let loggerProvider: @Sendable () -> LoggingService

    /// - Parameters:
    ///   - label: 队列名（与 `DispatchQueue(label:)` 语义一致，供线程采样识别）
    ///   - thresholdMs: 排队等待告警阈值（毫秒）
    ///   - logger: 日志服务（缺省取全局，测试可注入）
    public init(label: String,
                thresholdMs: Double = DatabaseQueue.slowWaitThresholdMs,
                logger: @escaping @Sendable () -> LoggingService = { AppContext.shared.logger }) {
        self.queue = DispatchQueue(label: label)
        self.thresholdMs = thresholdMs
        self.loggerProvider = logger
    }

    /// 同步执行；`caller` 缺省取调用方函数名（默认参数在调用点展开）
    @discardableResult
    public func sync<T>(_ body: () -> T, caller: String = #function) -> T {
        let enqueuedAt = DispatchTime.now().uptimeNanoseconds
        var startedAt = enqueuedAt
        let result = queue.sync { () -> T in
            startedAt = DispatchTime.now().uptimeNanoseconds
            return body()
        }
        let finishedAt = DispatchTime.now().uptimeNanoseconds
        let waitedMs = Double(startedAt &- enqueuedAt) / 1_000_000
        guard waitedMs > thresholdMs else { return result }
        let ranMs = Double(finishedAt &- startedAt) / 1_000_000
        loggerProvider().warning(String(format: "DB 队列排队等待 %.0f ms（执行 %.0f ms）— %@",
                                        waitedMs, ranMs, caller))
        return result
    }
}
