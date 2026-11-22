import Foundation

// MARK: - 会话扫描单元（多行来源 → 按会话归并）

/// 一个扫描单元：某来源里**一个会话**的全部用量事件
///
/// 为什么文件型之外还需要它：Gemini 的**一个文件可能装多个会话**（按 `sessionId` 分组），
/// SQLite 源（Copilot / OpenCode / Zed）整库是一份数据、会话是库里的一行 message / 一个 thread。
/// 两者都先把「解析器给出的事件流」按会话键归并成单元，再交给索引主流程 —— 于是多来源与
/// 文件型来源完全同形：同一个 scan 入口、同一套 (size, mtime) 增量判据、同一条落库路径。
public struct TokenSourceSessionUnit: Sendable, Equatable {
    /// 扫描记录键：`<文件或 db 路径>#<会话键>`（会话级的全局唯一标识）
    public let path: String
    /// 会话键（落库的 session_id，必须与事件里的 sessionID 一致，否则删除会删空）
    public let sessionKey: String
    /// 事件所属来源
    public let source: TokenSourceID
    /// 该单元全部事件（sessionID 已统一成 sessionKey）
    public let events: [HarnessTokenEvent]
    /// 会话工作目录（取不到为空串）
    public let cwd: String
    /// 坏行 / 坏记录数（只在同一批的第一个单元上记一次，避免按单元重复累加）
    public let malformedCount: Int
    /// 与统计无关的行数（同上，只记一次）
    public let ignoredCount: Int

    /// 落成本次扫描结果（索引主流程只认这个结构）
    public var scanResult: HarnessSessionScanResult {
        HarnessSessionScanResult(sessionID: sessionKey, cwd: cwd, events: events,
                                 totalLines: events.count + malformedCount + ignoredCount,
                                 malformedLines: malformedCount, ignoredLines: ignoredCount)
    }
}

/// 事件流 → 会话扫描单元（纯函数；Gemini 文件与 SQLite 库共用一套归并口径）
public enum TokenSourceSessionUnits {

    /// 把报告里的事件按会话键归并成单元（顺序 = 首次出现顺序，同一份数据两次归并结果一致）
    ///
    /// - Parameters:
    ///   - pathPrefix: 扫描记录键前缀（Gemini 是文件路径，SQLite 是 db 路径）
    ///   - fallbackSessionKey: 事件与元信息都取不到会话键时的兜底
    public static func units(
        from report: TokenSourceParseReport,
        pathPrefix: String,
        fallbackSessionKey: String
    ) -> [TokenSourceSessionUnit] {
        var order: [String] = []
        var grouped: [String: [TokenSourceUsageEvent]] = [:]
        for event in report.events {
            let key = sessionKey(for: event.sessionKey, report: report, fallback: fallbackSessionKey)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(event)
        }
        // 零事件也要给一个单元：让「有数据但一条用量都没有」与「根本没装」在状态点上分开
        if order.isEmpty {
            let key = sessionKey(for: report.session?.sessionKey ?? "", report: report,
                                 fallback: fallbackSessionKey)
            order = [key]
            grouped[key] = []
        }
        return order.enumerated().map { index, key in
            let rawEvents = grouped[key] ?? []
            let events = rawEvents.map { event in
                HarnessTokenEvent(sessionID: key, cwd: event.cwd, provider: event.provider,
                                 model: event.model, tsMs: event.tsMs, usage: event.usage,
                                 source: event.source)
            }
            let cwd = events.first(where: { !$0.cwd.isEmpty })?.cwd ?? report.session?.cwd ?? ""
            return TokenSourceSessionUnit(
                path: scanPath(prefix: pathPrefix, sessionKey: key),
                sessionKey: key,
                source: report.source,
                events: events,
                cwd: cwd,
                malformedCount: index == 0 ? report.malformedLineCount : 0,
                ignoredCount: index == 0 ? report.ignoredLineCount + report.skippedLineCount : 0
            )
        }
    }

    /// 扫描记录键：前缀 + `#` + 会话键
    ///
    /// 必须带上前缀：同一会话键（如 threadID）在不同库里可能重名，只有「路径 + 会话键」
    /// 才能唯一标识一个扫描单元；反过来只拼会话键会让换库后的记录互相覆盖。
    public static func scanPath(prefix: String, sessionKey: String) -> String {
        prefix + "#" + sessionKey
    }

    /// 会话键归一：Zed 的差额记录归回原 thread（一条 thread 就是一个会话）
    ///
    /// 差额记录是解析器为了保证「四桶合计与 cumulative 对齐」补出来的合成行，
    /// 它属于同一个 thread；若各自成一个会话，会话数会凭空翻倍。
    public static func normalizedSessionKey(_ key: String, source: TokenSourceID) -> String {
        guard source == .zed, key.hasSuffix(ZedThreadParser.remainderSessionSuffix) else { return key }
        let trimmed = String(key.dropLast(ZedThreadParser.remainderSessionSuffix.count))
        return trimmed.isEmpty ? key : trimmed
    }

    /// 事件/元信息里的会话键 → 单元键（空串按报告元信息 → 兜底逐级回落）
    private static func sessionKey(
        for raw: String,
        report: TokenSourceParseReport,
        fallback: String
    ) -> String {
        let candidates = [raw, report.session?.sessionKey ?? "", fallback]
        for candidate in candidates where !candidate.isEmpty {
            return normalizedSessionKey(candidate, source: report.source)
        }
        return report.source.rawValue
    }
}
