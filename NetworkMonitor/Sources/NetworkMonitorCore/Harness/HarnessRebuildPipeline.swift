import Foundation

// MARK: - 重建范围

/// 重建范围 —— 决定清理哪些索引数据，随后从会话文件重新读取
///
/// 语义边界（必须理解，否则会出现「清了却永远不回来」的假清空）：
/// 索引的增量判据是 `harness_session_scan` 的 (size, mtime)，
/// 只删事件不删扫描记录，下一轮会把该会话判成「未变更」直接跳过 ——
/// 因此清理动作**必须同时删扫描记录**，让这些会话重新从文件读一遍。
public enum HarnessRebuildScope: Sendable, Equatable {
    /// 清空全部索引（事件 + 扫描记录），随后全量重建
    case full
    /// 只清理「最近 days 天内出现过事件」的会话（事件 + 扫描记录），随后重扫这些会话
    case sinceDays(Int)

    /// 供 UI 展示的范围说明
    public var displayName: String {
        switch self {
        case .full: return "全部历史数据"
        case .sinceDays(let days): return "最近 " + String(max(1, days)) + " 天的会话数据"
        }
    }

    /// 合并两个范围：取覆盖更广的那个（full 吞掉一切）
    public static func merge(_ lhs: HarnessRebuildScope?, _ rhs: HarnessRebuildScope?) -> HarnessRebuildScope? {
        switch (lhs, rhs) {
        case (.some(.full), _), (_, .some(.full)): return .full
        case (.some(.sinceDays(let a)), .some(.sinceDays(let b))): return .sinceDays(max(a, b))
        case (.some(let scope), .none): return scope
        case (.none, .some(let scope)): return scope
        case (.none, .none): return nil
        }
    }
}

// MARK: - 重建回执

/// 重建回执 —— UI 用它回答「清了多少 / 扫了多少 / 索引了多少 / 耗时多久」
public struct HarnessRebuildReceipt: Sendable, Equatable {
    /// 本次请求的范围（nil = 只做增量，没有清理动作）
    public let scope: HarnessRebuildScope?
    /// 清理掉的事件行数
    public let eventsDeleted: Int
    /// 本轮写入的事件行数
    public let eventsIndexed: Int
    /// 实际扫描的会话数
    public let sessionsScanned: Int
    /// 因 (size, mtime) 未变更而跳过的会话数
    public let sessionsSkipped: Int
    /// 扫描 / 落库失败的会话数
    public let sessionsFailed: Int
    /// 本轮耗时（秒）
    public let elapsed: TimeInterval
    /// 是否因为上一轮还在跑而排队等待过（不静默丢弃，UI 可据此提示）
    public let waitedForRunningRun: Bool

    public init(scope: HarnessRebuildScope?,
                eventsDeleted: Int,
                eventsIndexed: Int,
                sessionsScanned: Int,
                sessionsSkipped: Int,
                sessionsFailed: Int,
                elapsed: TimeInterval,
                waitedForRunningRun: Bool) {
        self.scope = scope
        self.eventsDeleted = eventsDeleted
        self.eventsIndexed = eventsIndexed
        self.sessionsScanned = sessionsScanned
        self.sessionsSkipped = sessionsSkipped
        self.sessionsFailed = sessionsFailed
        self.elapsed = elapsed
        self.waitedForRunningRun = waitedForRunningRun
    }

    /// 一句话结果文案（面板 / 设置页共用）
    public var summaryText: String {
        var parts: [String] = []
        if let scope {
            parts.append("已清理 " + scope.displayName + "（" + String(eventsDeleted) + " 条事件）")
        }
        parts.append("扫描 " + String(sessionsScanned) + " 个会话")
        if sessionsSkipped > 0 { parts.append("跳过 " + String(sessionsSkipped) + " 个未变更") }
        if sessionsFailed > 0 { parts.append("失败 " + String(sessionsFailed) + " 个") }
        parts.append("索引 " + String(eventsIndexed) + " 条事件")
        parts.append("耗时 " + String(format: "%.1fs", elapsed))
        return parts.joined(separator: " · ")
    }
}

// MARK: - 重建请求

/// 一次索引请求（scope 为 nil 表示只做增量，不清理）
public struct HarnessIndexRequest: Sendable {
    /// 清理范围；nil = 增量
    public let scope: HarnessRebuildScope?
    /// 完成回调（收到本轮回执；数据源不可用时为 nil）
    public let completion: (@Sendable (HarnessRebuildReceipt?) -> Void)?

    public init(scope: HarnessRebuildScope?,
                completion: (@Sendable (HarnessRebuildReceipt?) -> Void)?) {
        self.scope = scope
        self.completion = completion
    }
}

/// 一次被取出执行的请求批次（多个入队请求合并成一轮，避免排队时逐条空转）
public struct HarnessIndexBatch: Sendable {
    /// 合并后的清理范围（nil = 只做增量）
    public let scope: HarnessRebuildScope?
    /// 本批次要回调的完成闭包
    public let completions: [@Sendable (HarnessRebuildReceipt?) -> Void]

    public init(scope: HarnessRebuildScope?, completions: [@Sendable (HarnessRebuildReceipt?) -> Void]) {
        self.scope = scope
        self.completions = completions
    }
}

// MARK: - 重建排队器

/// 重建请求排队器 —— 索引进行中收到的新请求**不静默丢弃**
///
/// 旧实现：`beginRun()` 失败就 return（完成回调照常触发），用户点「重新扫描」
/// 在索引进行中会毫无反应也不报错。现在改为入队 + 按最广范围合并，
/// 当前轮结束时继续 drain，用户看到的是「排队后确实跑了一轮」。
public final class HarnessRebuildQueue: @unchecked Sendable {

    private let lock = NSLock()
    private var pending: [HarnessIndexRequest] = []

    public init() {}

    /// 是否有排队项（当前轮结束前据此决定是否继续 drain）
    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending.isEmpty
    }

    /// 入队一次请求
    public func enqueue(_ request: HarnessIndexRequest) {
        lock.lock()
        pending.append(request)
        lock.unlock()
    }

    /// 取出全部排队项并合并成一批；队列为空返回 nil
    public func drain() -> HarnessIndexBatch? {
        lock.lock()
        let requests = pending
        pending.removeAll()
        lock.unlock()
        guard !requests.isEmpty else { return nil }
        var scope: HarnessRebuildScope?
        var completions: [@Sendable (HarnessRebuildReceipt?) -> Void] = []
        for request in requests {
            scope = HarnessRebuildScope.merge(scope, request.scope)
            if let completion = request.completion { completions.append(completion) }
        }
        return HarnessIndexBatch(scope: scope, completions: completions)
    }
}
