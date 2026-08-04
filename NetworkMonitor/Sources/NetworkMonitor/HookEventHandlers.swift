import AppKit
import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - Hook 事件处理器实现

/// 事件流水与会话汇总写入处理器（处理所有事件）
///
/// 职责：将事件写入 `hook_events` 流水表，并按会话生命周期更新 `hook_sessions` 汇总。
final class HookPersistenceHandler: HookEventHandler {
    let handledTypes: Set<ReasonixHookEventType> = []

    private let database: any HookEventRepository

    init(database: any HookEventRepository) {
        self.database = database
    }

    func handle(_ event: ReasonixHookEvent) {
        // 1. 写入事件流水
        database.writeHookEvent(event: event)

        // 2. 更新会话汇总
        if event.isSessionStart || event.isSessionEnd || event.isStop || event.isStopFailure {
            database.upsertHookSession(event: event)
        }
    }
}

/// 工具调用生命周期处理器（PreToolUse / PostToolUse / PostToolUseFailure）
final class ToolCallLifecycleHandler: HookEventHandler {
    let handledTypes: Set<ReasonixHookEventType> = [.preToolUse, .postToolUse, .postToolUseFailure]

    private let database: any HookEventRepository
    private let logger: LoggingService

    init(database: any HookEventRepository, logger: LoggingService) {
        self.database = database
        self.logger = logger
    }

    func handle(_ event: ReasonixHookEvent) {
        if event.isToolStart {
            let toolName = event.toolName ?? "unknown"
            var argsJSON: String? = nil
            if let args = event.toolArgs,
               let jsonData = try? JSONSerialization.data(withJSONObject: args, options: .sortedKeys) {
                argsJSON = String(data: jsonData, encoding: .utf8)
            }
            database.startHookToolCall(
                sessionId: event.sessionId,
                turn: event.turns,
                toolName: toolName,
                toolArgsJSON: argsJSON,
                timestamp: event.timestamp
            )
            logger.debug("工具调用开始: \(toolName)")
        }

        if event.isToolEnd {
            let toolName = event.toolName ?? "unknown"
            let isSuccess = event.eventType == .postToolUse
            let status = isSuccess ? "success" : "failure"
            let resultPreview = isSuccess ? event.resultPreview : nil
            let error = isSuccess ? nil : event.errorInfo

            database.finishHookToolCall(
                sessionId: event.sessionId,
                turn: event.turns,
                toolName: toolName,
                status: status,
                resultPreview: resultPreview,
                error: error,
                timestamp: event.timestamp
            )
            logger.debug("工具调用结束: \(toolName) [\(status)]")
        }
    }
}

/// 轮次完成/失败通知处理器（Stop / StopFailure）
///
/// 计算本轮增量 Token/花费并弹出系统通知；sidecar 数据缺失时重试加载并回填数据库。
final class SessionEndNotifier: @unchecked Sendable, HookEventHandler {
    let handledTypes: Set<ReasonixHookEventType> = [.stop, .stopFailure]

    private let database: any DatabaseService & HookEventRepository
    /// 日志服务
    private let logger: LoggingService
    /// 侧车数据加载器（由监听器注入，复用其 TTL/LRU 缓存）
    private let sidecarProvider: (ReasonixHookEvent) -> SessionSidecarData
    /// sessionId → 上一次 Stop 累计值缓存（避免历史坏数据导致增量计算错误）
    private var lastStopTotal: [String: (tokens: Int, cost: Double)] = [:]

    init(database: any DatabaseService & HookEventRepository,
         logger: LoggingService,
         sidecarProvider: @escaping (ReasonixHookEvent) -> SessionSidecarData) {
        self.database = database
        self.logger = logger
        self.sidecarProvider = sidecarProvider
    }

    func handle(_ event: ReasonixHookEvent) {
        let project = event.project.isEmpty ? "默认项目" : event.project
        let isFailure = event.isStopFailure
        let statusStr = isFailure ? "❌ 失败" : "✅ 完成"

        // 计算本轮增量：优先查内存缓存，未命中则查数据库
        let sid = event.sessionId
        let prev: (tokens: Int, cost: Double)
        if let cached = lastStopTotal[sid] {
            prev = cached
        } else {
            prev = previousStopTotal(for: sid)
        }

        // 如果 totalTokens 为 0，可能是 sidecar 文件尚未就绪，重试加载
        var effectiveEvent = event
        if effectiveEvent.totalTokens == 0 {
            let sidecar = sidecarProvider(effectiveEvent)
            if sidecar.totalTokens > 0 {
                effectiveEvent.enrich(from: sidecar)
                // 侧车数据为 USD，需再次转换为 CNY 保持一致
                effectiveEvent.cost = CurrencyConfig.usdToCny(effectiveEvent.cost)
                // 回写数据库，修复记录
                let safeId = Self.sanitizeSessionID(sid)
                let updateSQL = """
                    UPDATE hook_events SET total_tokens = \(effectiveEvent.totalTokens), cost = \(effectiveEvent.cost)
                    WHERE session_id = '\(safeId)' AND event_type IN ('Stop', 'StopFailure')
                      AND id = (SELECT MAX(id) FROM hook_events WHERE session_id = '\(safeId)' AND event_type IN ('Stop', 'StopFailure'))
                    """
                database.query(sql: updateSQL) { _ in }
                logger.info("回填 sidecar 数据: session=\(sid.prefix(30))... tokens=\(effectiveEvent.totalTokens) cost=\(effectiveEvent.cost)")
            }
            // sidecar 仍无数据时不兜底：token 统计以官方 stats JSONL 为权威来源，
            // 避免把全局累计值写入单个会话导致增量计算错误。
        }

        let roundTokens = effectiveEvent.totalTokens - prev.tokens
        let roundCost = effectiveEvent.cost - prev.cost   // 数据库与事件均为 CNY
        // 更新缓存供后续 Stop 事件使用
        lastStopTotal[sid] = (effectiveEvent.totalTokens, effectiveEvent.cost)

        // 失败事件无论是否有消耗都通知用户；普通 Stop 仅当有消耗时通知
        if !isFailure {
            guard roundTokens > 0 else { return }
        }

        // 格式化
        let tokensStr = FormatUtils.tokenShort(roundTokens)
        let costStr = FormatUtils.costShort(roundCost)

        // 清理过期通知（超过 5 分钟）和超量通知（最多 5 条）
        cleanupNotifications()

        let notification = NSUserNotification()
        notification.title = "\(project) — 轮次 \(statusStr)"
        notification.informativeText = "Token 消耗: \(tokensStr), 金额: \(costStr)"
        notification.soundName = NSUserNotificationDefaultSoundName

        // 保存会话文件路径到 userInfo，点击时用来跳转
        let slug = ReasonixPath.workspaceSlug(cwd: event.cwd)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionFile = "\(home)/.reasonix/projects/\(slug)/sessions/\(sid).jsonl"
        notification.userInfo = [
            "sessionFile": sessionFile,
            "sentAt": Date().timeIntervalSince1970
        ]

        NSUserNotificationCenter.default.deliver(notification)
    }

    /// 从数据库查询该 session 上一次有效的 Stop/StopFailure 累计值
    /// 排除 total_tokens=0 的无效记录（sidecar 加载失败时遗留的坏数据）
    private func previousStopTotal(for sessionId: String) -> (tokens: Int, cost: Double) {
        let safeId = Self.sanitizeSessionID(sessionId)
        let sql = """
            SELECT COALESCE(total_tokens, 0), COALESCE(cost, 0.0)
            FROM hook_events
            WHERE session_id = '\(safeId)'
              AND event_type IN ('Stop', 'StopFailure')
              AND total_tokens > 0
              AND id < (SELECT COALESCE(MAX(id), 0) FROM hook_events
                        WHERE session_id = '\(safeId)' AND event_type IN ('Stop', 'StopFailure') AND total_tokens > 0)
            ORDER BY id DESC LIMIT 1
            """
        var tokens = 0
        var cost = 0.0
        database.query(sql: sql) { stmt in
            tokens = Int(sqlite3_column_int(stmt, 0))
            cost = sqlite3_column_double(stmt, 1)
        }
        return (tokens, cost)
    }

    /// 清理过期和超量的通知
    private func cleanupNotifications() {
        let center = NSUserNotificationCenter.default
        let now = Date().timeIntervalSince1970
        let maxAge: TimeInterval = 300  // 5 分钟
        let maxCount = 5

        var remaining: [NSUserNotification] = []
        for note in center.deliveredNotifications {
            guard let info = note.userInfo,
                  let sentAt = info["sentAt"] as? TimeInterval else {
                center.removeDeliveredNotification(note)
                continue
            }
            // 超过 5 分钟的移除
            if now - sentAt > maxAge {
                center.removeDeliveredNotification(note)
                continue
            }
            remaining.append(note)
        }

        // 超过 5 条的移除最旧的
        if remaining.count >= maxCount {
            // 按发送时间排序，移除最旧的
            remaining.sort { a, b in
                let aTime = a.userInfo?["sentAt"] as? TimeInterval ?? 0
                let bTime = b.userInfo?["sentAt"] as? TimeInterval ?? 0
                return aTime < bTime
            }
            let toRemove = remaining.prefix(remaining.count - maxCount + 1)
            for note in toRemove {
                center.removeDeliveredNotification(note)
            }
        }
    }

    /// 净化 sessionId，仅保留字母数字和常见分隔符
    private static func sanitizeSessionID(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }
}

/// stats JSONL 增量导入触发处理器（处理所有事件）
///
/// 每次事件后触发官方 stats JSONL 增量导入（幂等 + 节流），
/// 保证菜单栏统计与 reasonix 软件同源、实时。
final class StatsSyncHandler: HookEventHandler {
    let handledTypes: Set<ReasonixHookEventType> = []

    private let statsImporter: StatsImporter

    init(statsImporter: StatsImporter) {
        self.statsImporter = statsImporter
    }

    func handle(_ event: ReasonixHookEvent) {
        statsImporter.syncIfNeeded()
    }
}
