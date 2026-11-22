import Foundation

// MARK: - OpenCode 消息用量解析（SQLite 消息表：v1 message / v2 session_message）

/// OpenCode（SQLite 版）用量解析器
///
/// 位置：`~/.local/share/opencode/opencode.db`（WAL；`OPENCODE_DB` 与渠道后缀库见
/// `OpenCodeDatabaseLocation`）。CLI 可能正持有它，故**只读打开**
/// （SQLITE_OPEN_READONLY + PRAGMA query_only），绝不建表 / checkpoint / 写 journal。
///
/// **库结构两代并存**：上游已从 sst/opencode 迁到 anomalyco/opencode，v2 线把表名整套换了
/// （session / message / part → session_v2 / session_message / session_part），v1 线仍在维护。
/// 所以读库前先按 sqlite_master 嗅探（见 OpenCodeSchema），两代只走**一条**查询路径——
/// 并存时优先「有数据」的那代，绝不两表都读（会双计）。
///
/// 四桶口径（设计规格 §2.5 / §2.7，换算已对照上游确认）：
/// - uncachedInput = tokens.input（OpenCode 的 input **不含**缓存）；
/// - output = tokens.output + tokens.reasoning（reasoning 是单列的思考 token）；
/// - cacheRead = tokens.cache.read、cacheWrite = tokens.cache.write；cache 是对象，不是数字；
/// - cost 常为 0（本地 / 订阅 provider），**不参与**统计。
/// 两代 tokens 形状相同（packages/schema/src/token-usage.ts），差异只在 model 的位置，
/// 由 OpenCodeUsageShape 兜住；total 是派生值，五桶能拆就不看它。
///
/// **只读消息层、不读分片层（part / session_part）**：分片里也带 tokens（v1 的 step-finish、
/// v2 的 step 分片），而 session 表的累加列正是上游从 step 事件聚合出来的（projector.ts），
/// 消息层与分片层是同一笔用量的两个投影，两处都读会双计。消息层的 data.tokens 是
/// **该消息（一次 step = 一次模型请求）的用量快照**：message-updater.ts 里 session.step.ended
/// 是**赋值** draft.tokens = event.data.tokens 而非累加，且 session.step.started 会给新 step
/// 新建一条 assistant 消息，故「按消息级取」即全量。风险留档：若上游改成「一条消息承接多个
/// step」且仍用赋值语义，会少算，届时需回归这里。
///
/// **不按 role / type 过滤**：compaction 消息同样带 cost / tokens（v2 的 CompactionUsage，
/// 语义是「压缩请求自身」的用量），丢掉它就是漏账；v2 的 message.data 落库时还被剥掉了
/// id / type，本就无法按类型判断——只认 data.tokens。
///
/// **compaction 的 model 靠会话行兜底**：它只记 cost / tokens、不带 model，直接取会落成
/// `opencode/unknown`；会话行有 model 列（v2 的 `session_v2.model` = `{id, providerID}`）就用它。
///
/// 子 agent 会话（parent_id 非空）照常计入：它们同样是真发生的请求；
/// cwd 取会话表的 directory，时间取 time_created（unix 毫秒）。
public enum OpenCodeMessageParser {
    public static let source: TokenSourceID = .opencode
    /// 库文件名（只有默认形态；渠道后缀库与 `OPENCODE_DB` 覆盖见 `OpenCodeDatabaseLocation`）
    public static let databaseFileName = OpenCodeDatabaseLocation.defaultFileName
    /// 旧版 JSON 树目录名（本轮不接，仅用于诊断说明）
    public static let legacyStorageDirectoryName = "storage"
    public static let unknownModel = "unknown"
    /// data.providerID 缺失时的兜底（取来源自身标识）
    public static let unknownProvider = "opencode"

    // MARK: - 行模型（IO 与解析的分界）

    /// 消息表里与用量相关的一行（两代同形：id / session_id / time_created / data）
    public struct MessageRow: Sendable, Equatable {
        /// 消息 id（表主键；重复行按它兜底去重）
        public let id: String
        /// 所属会话（会话表的 id）
        public let sessionID: String
        /// time_created，unix 毫秒
        public let timeCreatedMs: Int64
        /// data 列原文（JSON）
        public let data: Data

        public init(id: String, sessionID: String, timeCreatedMs: Int64, data: Data) {
            self.id = id
            self.sessionID = sessionID
            self.timeCreatedMs = timeCreatedMs
            self.data = data
        }
    }

    /// 会话表里与用量相关的字段（两代同形：v1 session / v2 session_v2）
    public struct SessionRow: Sendable, Equatable {
        public let id: String
        /// 会话工作目录（即 cwd）
        public let directory: String
        /// 非空 = 子 agent 会话（照常计入，只用于诊断）
        public let parentID: String?
        /// 会话的模型（库里 model 列的解析结果；缺列 / 没写 = nil），给 compaction 兜底
        public let model: OpenCodeSessionModel?

        public init(id: String, directory: String, parentID: String? = nil,
                    model: OpenCodeSessionModel? = nil) {
            self.id = id
            self.directory = directory
            self.parentID = parentID
            self.model = model
        }
    }

    // MARK: - 纯函数入口

    /// 单行入口：一行消息 data + 该行的时间 / 会话 → 统一事件（永不抛错）
    ///
    /// - Parameter fallbackModel: 消息自身没带 model 时用的兜底（compaction 就属于这类）。
    public static func parse(
        data: Data,
        timeCreatedMs: Int64,
        sessionID: String,
        cwd: String = "",
        fallbackModel: OpenCodeSessionModel? = nil
    ) -> TokenSourceLineResult {
        guard !TokenSourceJSON.isBlank(data) else { return .ignored }
        guard let root = TokenSourceJSON.object(from: data) else {
            return .malformed("消息行 data 不是 JSON 对象")
        }
        // 用户 / 系统消息没有 tokens：与统计无关，不是坏行
        guard let tokens = TokenSourceJSON.object(root["tokens"]) else { return .ignored }
        // 没有可解析时间就无法分天：算坏行，不按 0 记账（0 会把数据全挤到 1970）
        guard timeCreatedMs > 0 else { return .malformed("消息行缺少可用的 time_created") }
        let usage = OpenCodeUsageShape.usage(from: tokens)
        // 全零 tokens 的行不是一次真实请求（例如只有元信息的消息）
        guard usage.totalTokens > 0 else { return .ignored }
        let model = resolvedModel(root: root, fallback: fallbackModel)
        return .usage(TokenSourceUsageEvent(
            source: source,
            tsMs: timeCreatedMs,
            provider: model.provider,
            model: model.model,
            usage: usage,
            sessionKey: sessionID,
            cwd: cwd
        ))
    }

    /// 整表入口（fixture 直接驱动）：若干行 + 会话表 → 与会话型解析器同形的报告
    ///
    /// 按消息 id 兜底去重：主键已保证唯一，但 JOIN 放大 / 重复导出时按 id 仍只算一次。
    public static func parse(
        rows: [MessageRow],
        sessions: [SessionRow] = []
    ) -> TokenSourceParseReport {
        var directoryBySession: [String: String] = [:]
        var modelBySession: [String: OpenCodeSessionModel] = [:]
        for session in sessions where directoryBySession[session.id] == nil {
            directoryBySession[session.id] = session.directory
        }
        // 同一会话出现多行时取第一份**有模型**的（行序不保证，空值不能盖住有效值）
        for session in sessions where modelBySession[session.id] == nil {
            if let model = session.model { modelBySession[session.id] = model }
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
                         sessionID: row.sessionID, cwd: cwd,
                         fallbackModel: modelBySession[row.sessionID]) {
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

    /// 给定 db 路径：整库读取 + 解析；不存在 / 打不开 / 表名不认识 → 空事件 + 降级原因（不抛）
    public static func read(databaseAt url: URL) -> TokenSourceSQLiteReadReport {
        read(databaseAt: url.path)
    }

    /// 给定 db 路径：整库读取 + 解析；不存在 / 打不开 / 表名不认识 → 空事件 + 降级原因（不抛）
    ///
    /// 可选**对账基准**：v2 的 session_v2 上还有累加列 cost 与 tokens_input / tokens_output /
    /// tokens_reasoning / tokens_cache_read / tokens_cache_write。那不是权威总量、也**没有时间分布**
    /// （无法分天 / 分时），故不参与统计，只适合拿来对账「本解析器按消息表算出的四桶合计」
    /// 是否与上游聚合一致。
    ///
    /// 旧 JSON 树（storage/...）在 v2 迁移期间仍可能留存：有 db 就只读 db（否则同一批用量被双算），
    /// db 不存在直接返回「无数据」，**不回退去扫 JSON 树**；若发现迁移期缺数，可回看 storage 树。
    public static func read(databaseAt path: String) -> TokenSourceSQLiteReadReport {
        switch TokenSourceSQLiteAccess.openReadOnly(path: path) {
        case .failure(let reason):
            return .unavailable(source, reason)
        case .success(let db):
            defer { TokenSourceSQLiteAccess.close(db) }
            // 结构嗅探：v1 / v2 表名并存时也只走一条路径（优先有数据的那代），避免双计
            let candidates = OpenCodeSchema.candidates(tableNames: OpenCodeSchema.tableNames(db))
            let schema = OpenCodeSchema.resolve(candidates) {
                OpenCodeSchema.hasAnyRow(db, table: $0)
            }
            guard let schema else {
                // 坏文件的 table_info 同样是空结果：能读 sqlite_master 才是真的缺表
                if let message = TokenSourceSQLiteAccess.readError(db) {
                    return .unavailable(source, .openFailed(path: path, message: message))
                }
                // 两代表名都没命中：按 v1 的表名报原因（文案与旧版一致，便于对账）
                return .unavailable(source, .tableMissing(table: OpenCodeSchema.v1.messageTable))
            }
            guard hasRequiredColumns(db, messageTable: schema.messageTable) else {
                // 表在但列不认识（上游改了列名）：不猜列，按结构不符降级
                return .unavailable(source, .tableMissing(table: schema.messageTable))
            }
            // 会话表缺失不致命：cwd 退化为空串，消息照常计入。
            // model 列按存在性探测：硬拼未知列会让整条查询失败，退化成「整源不可用」
            let sessionColumns = Set(TokenSourceSQLiteAccess.columnNames(db, table: schema.sessionTable))
            let hasModelColumn = sessionColumns.contains(OpenCodeSchema.sessionModelColumn)
            var sessions: [SessionRow] = []
            _ = TokenSourceSQLiteAccess.forEachRow(db, sql: schema.sessionSQL(hasModelColumn: hasModelColumn)) { row in
                guard let id = TokenSourceJSON.string(row["id"]) else { return }
                sessions.append(SessionRow(
                    id: id,
                    directory: TokenSourceJSON.string(row["directory"]) ?? "",
                    parentID: TokenSourceJSON.string(row["parent_id"]),
                    model: hasModelColumn
                        ? OpenCodeSessionModel.parse(column: row[OpenCodeSchema.sessionModelColumn])
                        : nil
                ))
            }
            var rows: [MessageRow] = []
            let readError = TokenSourceSQLiteAccess.forEachRow(db, sql: schema.messageSQL) { row in
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

    /// 消息模型：自带用自带的，没带（compaction）用会话兜底，都没有才落 unknown
    private static func resolvedModel(
        root: [String: Any],
        fallback: OpenCodeSessionModel?
    ) -> (provider: String, model: String) {
        if OpenCodeSessionModel.messageHasOwnModel(root) {
            return OpenCodeUsageShape.model(from: root, unknownProvider: unknownProvider,
                                            unknownModel: unknownModel)
        }
        guard let fallback else {
            return (provider: unknownProvider, model: unknownModel)
        }
        return (provider: fallback.provider, model: fallback.model)
    }

    /// 消息表是否具备必需列（缺一列就按「表名不认识」处理，不猜列名）
    private static func hasRequiredColumns(_ db: OpaquePointer, messageTable: String) -> Bool {
        let columns = Set(TokenSourceSQLiteAccess.columnNames(db, table: messageTable))
        return OpenCodeSchema.requiredMessageColumns.allSatisfy { columns.contains($0) }
    }

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
}
