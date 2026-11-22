import Foundation

// MARK: - OpenCode 消息用量解析（SQLite `message` 表）

/// OpenCode（SQLite 版）用量解析器
///
/// 位置：`~/.local/share/opencode/opencode.db`（WAL）。CLI 可能正持有它，故**只读打开**
/// （`SQLITE_OPEN_READONLY` + `PRAGMA query_only`），绝不建表 / checkpoint / 写 journal。
///
/// 只接 SQLite：旧版 `~/.local/share/opencode/storage/` 的 JSON 树有三代格式并存，
/// 检测到 db 存在就**只用 db**（否则同一批用量被双算）；db 不存在直接返回「无数据」，
/// **不回退去扫 JSON 树**。
///
/// 四桶口径（设计规格 §2.5 / §2.7）：
/// - `uncachedInput = tokens.input`（OpenCode 的 input **不含**缓存）；
/// - `output = tokens.output + tokens.reasoning`（reasoning 是单列的思考 token）；
/// - `cacheRead = tokens.cache.read`、`cacheWrite = tokens.cache.write`；
/// - `cost` 常为 0（本地 / 订阅 provider），**不参与**统计。
///
/// 子 agent 会话（`session.parent_id` 非空）照常计入：它们同样是真发生的请求；
/// cwd 取 `session.directory`，时间取 `message.time_created`（unix 毫秒）。
public enum OpenCodeMessageParser {
    public static let source: TokenSourceID = .opencode
    /// 库文件名（`TokenSourceID.defaultRoots` 只给目录）
    public static let databaseFileName = "opencode.db"
    /// 旧版 JSON 树目录名（本轮不接，仅用于诊断说明）
    public static let legacyStorageDirectoryName = "storage"
    public static let unknownModel = "unknown"
    /// `data.providerID` 缺失时的兜底（取来源自身标识）
    public static let unknownProvider = "opencode"

    // MARK: - 行模型（IO 与解析的分界）

    /// `message` 表里与用量相关的一行
    public struct MessageRow: Sendable, Equatable {
        /// 消息 id（表主键；重复行按它兜底去重）
        public let id: String
        /// 所属会话（`session.id`）
        public let sessionID: String
        /// `time_created`，unix 毫秒
        public let timeCreatedMs: Int64
        /// `data` 列原文（JSON）
        public let data: Data

        public init(id: String, sessionID: String, timeCreatedMs: Int64, data: Data) {
            self.id = id
            self.sessionID = sessionID
            self.timeCreatedMs = timeCreatedMs
            self.data = data
        }
    }

    /// `session` 表里与用量相关的字段
    public struct SessionRow: Sendable, Equatable {
        public let id: String
        /// 会话工作目录（即 cwd）
        public let directory: String
        /// 非空 = 子 agent 会话（照常计入，只用于诊断）
        public let parentID: String?

        public init(id: String, directory: String, parentID: String? = nil) {
            self.id = id
            self.directory = directory
            self.parentID = parentID
        }
    }

    // MARK: - 纯函数入口

    /// 单行入口：一行 `message.data` + 该行的时间 / 会话 → 统一事件（永不抛错）
    public static func parse(
        data: Data,
        timeCreatedMs: Int64,
        sessionID: String,
        cwd: String = ""
    ) -> TokenSourceLineResult {
        guard !TokenSourceJSON.isBlank(data) else { return .ignored }
        guard let root = TokenSourceJSON.object(from: data) else {
            return .malformed("message.data 不是 JSON 对象")
        }
        // 用户 / 系统消息没有 tokens：与统计无关，不是坏行
        guard let tokens = TokenSourceJSON.object(root["tokens"]) else { return .ignored }
        // 没有可解析时间就无法分天：算坏行，不按 0 记账（0 会把数据全挤到 1970）
        guard timeCreatedMs > 0 else { return .malformed("message 行缺少可用的 time_created") }
        let usage = usage(from: tokens)
        // 全零 tokens 的行不是一次真实请求（例如只有元信息的消息）
        guard usage.totalTokens > 0 else { return .ignored }
        return .usage(TokenSourceUsageEvent(
            source: source,
            tsMs: timeCreatedMs,
            provider: TokenSourceJSON.string(root["providerID"]) ?? unknownProvider,
            model: TokenSourceJSON.string(root["modelID"]) ?? unknownModel,
            usage: usage,
            sessionKey: sessionID,
            cwd: cwd
        ))
    }

    /// 整表入口（fixture 直接驱动）：若干行 + 会话表 → 与会话型解析器同形的报告
    ///
    /// 按 `message.id` 兜底去重：主键已保证唯一，但 JOIN 放大 / 重复导出时按 id 仍只算一次。
    public static func parse(
        rows: [MessageRow],
        sessions: [SessionRow] = []
    ) -> TokenSourceParseReport {
        var directoryBySession: [String: String] = [:]
        for session in sessions where directoryBySession[session.id] == nil {
            directoryBySession[session.id] = session.directory
        }
        var events: [TokenSourceUsageEvent] = []
        var seenIDs: Set<String> = []
        var ignored = 0
        var malformed = 0
        var skipped = 0
        for row in rows {
            if !row.id.isEmpty, seenIDs.contains(row.id) {
                skipped += 1
                continue
            }
            let cwd = directoryBySession[row.sessionID] ?? ""
            switch parse(data: row.data, timeCreatedMs: row.timeCreatedMs,
                         sessionID: row.sessionID, cwd: cwd) {
            case .usage(let event):
                if !row.id.isEmpty { seenIDs.insert(row.id) }
                events.append(event)
            case .session:
                ignored += 1
            case .ignored:
                ignored += 1
            case .malformed:
                malformed += 1
            }
        }
        return TokenSourceParseReport(
            source: source,
            events: events,
            session: nil,
            ignoredLineCount: ignored,
            malformedLineCount: malformed,
            skippedLineCount: skipped
        )
    }

    // MARK: - 数据库入口（只读）

    /// 给定 db 路径：整库读取 + 解析；不存在 / 打不开 → 空事件 + 降级原因（不抛）
    public static func read(databaseAt url: URL) -> TokenSourceSQLiteReadReport {
        read(databaseAt: url.path)
    }

    /// 给定 db 路径：整库读取 + 解析；不存在 / 打不开 → 空事件 + 降级原因（不抛）
    public static func read(databaseAt path: String) -> TokenSourceSQLiteReadReport {
        switch TokenSourceSQLiteAccess.openReadOnly(path: path) {
        case .failure(let reason):
            return .unavailable(source, reason)
        case .success(let db):
            defer { TokenSourceSQLiteAccess.close(db) }
            // session 表缺失不致命：cwd 退化为空串，message 照常计入
            var sessions: [SessionRow] = []
            _ = TokenSourceSQLiteAccess.forEachRow(db, sql: sessionSQL) { row in
                guard let id = TokenSourceJSON.string(row["id"]) else { return }
                sessions.append(SessionRow(
                    id: id,
                    directory: TokenSourceJSON.string(row["directory"]) ?? "",
                    parentID: TokenSourceJSON.string(row["parent_id"])
                ))
            }
            guard !TokenSourceSQLiteAccess.columnNames(db, table: "message").isEmpty else {
                // 坏文件的 `table_info` 同样是空结果：能读 sqlite_master 才是真的缺表
                if let message = TokenSourceSQLiteAccess.readError(db) {
                    return .unavailable(source, .openFailed(path: path, message: message))
                }
                return .unavailable(source, .tableMissing(table: "message"))
            }
            var rows: [MessageRow] = []
            let readError = TokenSourceSQLiteAccess.forEachRow(db, sql: messageSQL) { row in
                guard let message = messageRow(from: row) else { return }
                rows.append(message)
            }
            if let readError {
                return .unavailable(source, .openFailed(path: path, message: readError))
            }
            let report = parse(rows: rows, sessions: sessions)
            return TokenSourceSQLiteReadReport(
                source: source,
                events: report.events,
                ignoredRowCount: report.ignoredLineCount,
                malformedRowCount: report.malformedLineCount,
                skippedRowCount: report.skippedLineCount
            )
        }
    }

    // MARK: - 内部

    /// 会话表只取必要三列（`…` 里还有大量 JSON 字段，别整行读）
    private static let sessionSQL = "SELECT id, directory, parent_id FROM session;"
    /// 消息表按时间排序读，事件顺序与真实发生顺序一致
    private static let messageSQL = "SELECT id, session_id, time_created, data FROM message ORDER BY time_created, id;"

    /// 一行 → 行模型；缺 data / 时间读不出来时返回 nil（由调用方按空行处理）
    private static func messageRow(from row: [String: Any]) -> MessageRow? {
        let data: Data
        if let blob = row["data"] as? Data {
            data = blob
        } else if let text = TokenSourceJSON.string(row["data"]) {
            data = Data(text.utf8)
        } else {
            return nil
        }
        return MessageRow(
            id: TokenSourceJSON.string(row["id"]) ?? "",
            sessionID: TokenSourceJSON.string(row["session_id"]) ?? "",
            timeCreatedMs: Int64(TokenSourceJSON.int(row["time_created"]) ?? 0),
            data: data
        )
    }

    /// 四桶映射：input 不含缓存；output 加上单列的 reasoning
    private static func usage(from tokens: [String: Any]) -> HarnessTokenUsage {
        let input = TokenSourceJSON.nonNegative(TokenSourceJSON.int(tokens["input"]) ?? 0)
        let output = TokenSourceJSON.nonNegative(TokenSourceJSON.int(tokens["output"]) ?? 0)
        let reasoning = TokenSourceJSON.nonNegative(TokenSourceJSON.int(tokens["reasoning"]) ?? 0)
        let cache = TokenSourceJSON.object(tokens["cache"])
        return HarnessTokenUsage(
            uncachedInput: input,
            output: output + reasoning,
            cacheRead: TokenSourceJSON.nonNegative(TokenSourceJSON.int(cache?["read"]) ?? 0),
            cacheWrite: TokenSourceJSON.nonNegative(TokenSourceJSON.int(cache?["write"]) ?? 0),
            requestCount: 1
        )
    }
}
