import Foundation
import SQLite3

// MARK: - OpenCode 库结构嗅探（v1 / v2 两代表名）

/// OpenCode 落库结构的两代布局
///
/// 上游仓库已从 `sst/opencode` 迁到 `anomalyco/opencode`（默认分支 `dev`），当前 v2 线
/// 与 v1 线并存，v2 把整套表名改了（`packages/core/src/session/sql.ts`）：
///
/// | 用途 | v1 | v2 |
/// |---|---|---|
/// | 会话 | `session` | `session_v2` |
/// | 消息 | `message` | `session_message` |
/// | 分片 | `part` | `session_part` |
///
/// 两代的消息表列名一致（`id` / `session_id` / `time_created` / `data`），所以读取路径只差表名；
/// `data` 里的 JSON 形状差异（`model` / `tokens` 位置）由 `OpenCodeUsageShape` 按字段兜住。
///
/// 结论：**读库前先按 `sqlite_master` 嗅探一次**，不要假定 `message` 表唯一存在。
public enum OpenCodeSchemaVersion: String, Sendable, Equatable, CaseIterable {
    /// v1 线（`session` / `message` / `part`）
    case v1
    /// v2 线（`session_v2` / `session_message` / `session_part`）
    case v2
}

/// 某一代布局用到的表名与查询语句
public struct OpenCodeSchema: Sendable, Equatable {
    public let version: OpenCodeSchemaVersion
    /// 会话表（取 cwd / 父会话）
    public let sessionTable: String
    /// 消息表（用量只从这里取，见 `OpenCodeMessageParser` 的口径说明）
    public let messageTable: String

    public init(version: OpenCodeSchemaVersion, sessionTable: String, messageTable: String) {
        self.version = version
        self.sessionTable = sessionTable
        self.messageTable = messageTable
    }

    /// 会话行里记录模型的列名（v2 的 `session_v2` 有；v1 的 `session` 随版本，故按列存在性决定读不读）
    public static let sessionModelColumn = "model"

    /// 会话表只取必要列（表里还有大量 JSON 字段，别整行读）
    ///
    /// - Parameter hasModelColumn: 列存在时多带一列 `model`（compaction 兜底用）。
    ///   缺列**不能**硬拼进 SELECT：SQLite 会因为未知列让整条查询失败，退化成「整源不可用」。
    public func sessionSQL(hasModelColumn: Bool) -> String {
        let columns = hasModelColumn
            ? "id, directory, parent_id, " + Self.sessionModelColumn
            : "id, directory, parent_id"
        return "SELECT " + columns + " FROM " + sessionTable + ";"
    }

    /// 消息表按时间排序读，事件顺序与真实发生顺序一致
    public var messageSQL: String {
        "SELECT id, session_id, time_created, data FROM " + messageTable + " ORDER BY time_created, id;"
    }

    /// v1 布局
    public static let v1 = OpenCodeSchema(version: .v1, sessionTable: "session", messageTable: "message")
    /// v2 布局
    public static let v2 = OpenCodeSchema(version: .v2, sessionTable: "session_v2", messageTable: "session_message")

    /// 消息表必须具备的列：缺任何一列都按「结构不认识」处理，不猜列名
    public static let requiredMessageColumns = ["id", "session_id", "time_created", "data"]

    // MARK: - 判定

    /// 库里出现了哪几代布局（按 `sqlite_master` 的表名；v2 排在前 = 并存时优先新线）
    public static func candidates(tableNames: Set<String>) -> [OpenCodeSchema] {
        var result: [OpenCodeSchema] = []
        if tableNames.contains(v2.messageTable) { result.append(v2) }
        if tableNames.contains(v1.messageTable) { result.append(v1) }
        return result
    }

    /// 选定本次读取采用的布局
    ///
    /// 迁移期两代消息表可能同时存在（v2 迁移脚本只写新表、旧表留档），此时按「谁有数据」选：
    /// 优先 v2 且有行 → 次选 v1 且有行 → 都没行则优先 v2（读出来就是 0 行，不会双计）。
    /// **只走一条读取路径**，绝不两张表都读。
    ///
    /// - Parameters:
    ///   - candidates: `candidates(tableNames:)` 的结果
    ///   - hasRows: 消息表是否有行的探针（表名 → 是否存在至少一行）
    public static func resolve(_ candidates: [OpenCodeSchema],
                               hasRows: (String) -> Bool) -> OpenCodeSchema? {
        if let withRows = candidates.first(where: { hasRows($0.messageTable) }) { return withRows }
        return candidates.first
    }

    // MARK: - 库内探针（只读）

    /// 库里的表名集合（`sqlite_master`；坏文件的 `PRAGMA table_info` 同样是空结果，故先看这里）
    static func tableNames(_ db: OpaquePointer) -> Set<String> {
        var names: Set<String> = []
        _ = TokenSourceSQLiteAccess.forEachRow(
            db, sql: "SELECT name FROM sqlite_master WHERE type = 'table';"
        ) { row in
            if let name = TokenSourceJSON.string(row["name"]) { names.insert(name) }
        }
        return names
    }

    /// 表里是否有至少一行（带 LIMIT 1，库再大也只读一行）
    static func hasAnyRow(_ db: OpaquePointer, table: String) -> Bool {
        var found = false
        _ = TokenSourceSQLiteAccess.forEachRow(db, sql: "SELECT 1 FROM " + table + " LIMIT 1;") { _ in
            found = true
        }
        return found
    }
}

// MARK: - 会话行模型（compaction 兜底）

/// 会话行里记录的模型（`session.model` / `session_v2.model`）
///
/// v2 的 `session_v2` 有 `model` 列（drizzle `text({mode:"json"})`，形如
/// `{"id":"claude-sonnet-4-5","providerID":"anthropic","variant":…}`）；v1 的 `session`
/// 是否有该列随版本而异，读取前按 `PRAGMA table_info` 探测，缺列就不读（不猜列名）。
///
/// 用途只有一个：**compaction 消息自身不带 model**（只记 cost / tokens），用所属会话的模型兜底，
/// 免得整批压缩用量落成 `opencode/unknown` 把模型排行算错。
public struct OpenCodeSessionModel: Sendable, Equatable {
    public let provider: String
    public let model: String

    public init(provider: String, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 从库里的 model 列取值（JSON 文本 / BLOB / 已解析对象）；取不到一对完整标识返回 nil
    public static func parse(column value: Any?) -> OpenCodeSessionModel? {
        let root: [String: Any]?
        if let data = value as? Data {
            root = TokenSourceJSON.object(from: data)
        } else if let text = TokenSourceJSON.string(value) {
            root = TokenSourceJSON.object(from: Data(text.utf8))
        } else {
            root = TokenSourceJSON.object(value)
        }
        guard let root else { return nil }
        // v2 落的是 {id, providerID}；旧版 / 其他写法的 {model, provider} / {modelID} 一并兼容
        guard let provider = TokenSourceJSON.string(root["providerID"])
            ?? TokenSourceJSON.string(root["provider"]),
            let model = TokenSourceJSON.string(root["id"])
                ?? TokenSourceJSON.string(root["modelID"])
                ?? TokenSourceJSON.string(root["model"]) else { return nil }
        return OpenCodeSessionModel(provider: provider, model: model)
    }

    /// 消息自身是否带模型标识（v2 的 `model{providerID,id}` / v1 的顶层 `modelID`）
    ///
    /// 不带 = 这条消息不是一次普通对话请求（compaction 只记 cost / tokens），该走会话兜底。
    public static func messageHasOwnModel(_ root: [String: Any]) -> Bool {
        if let nested = TokenSourceJSON.object(root["model"]),
           TokenSourceJSON.string(nested["id"]) != nil { return true }
        return TokenSourceJSON.string(root["modelID"]) != nil
    }
}

// MARK: - 嗅探结果（诊断 / 取证）

/// 库结构嗅探结果：诊断面板与取证脚本用它说明「这次按哪一代读的」
public struct OpenCodeSchemaProbe: Sendable, Equatable {
    /// 最终采用的布局（nil = 两代都不认识，读取会按「缺表」降级）
    public let schema: OpenCodeSchema?
    /// 库里实际存在的表名（排序后，便于诊断与取证对照）
    public let tables: [String]
    /// 采用的消息表是否已有数据（迁移期可用它判断「新表还没写数据」）
    public let messageTableHasRows: Bool
    /// 打不开库时的原因（nil = 打开成功）
    public let openFailure: String?

    public init(schema: OpenCodeSchema?, tables: [String],
                messageTableHasRows: Bool, openFailure: String? = nil) {
        self.schema = schema
        self.tables = tables
        self.messageTableHasRows = messageTableHasRows
        self.openFailure = openFailure
    }

    public var version: OpenCodeSchemaVersion? { schema?.version }
    public var isRecognized: Bool { schema != nil }

    /// 一行中文诊断（取证与回报都用它，避免各处自拼）
    public var summary: String {
        if let openFailure { return "库打不开（" + openFailure + "）" }
        let tableList = tables.isEmpty ? "（无表）" : tables.joined(separator: ", ")
        guard let schema else { return "表名不认识（库内表：" + tableList + "）" }
        let rows = messageTableHasRows ? "已有数据" : "暂无数据"
        return schema.version.rawValue + "（" + schema.messageTable + "，" + rows + "）；库内表：" + tableList
    }
}

public extension OpenCodeSchema {
    /// 给定 db 路径做一次结构嗅探（只读打开 → 判定 → 关闭；打不开也返回结果，不抛错）
    static func probe(databaseAt path: String) -> OpenCodeSchemaProbe {
        switch TokenSourceSQLiteAccess.openReadOnly(path: path) {
        case .failure(let reason):
            return OpenCodeSchemaProbe(schema: nil, tables: [], messageTableHasRows: false,
                                       openFailure: reason.displayMessage)
        case .success(let db):
            defer { TokenSourceSQLiteAccess.close(db) }
            let names = tableNames(db)
            let candidates = candidates(tableNames: names)
            let resolved = resolve(candidates) { hasAnyRow(db, table: $0) }
            return OpenCodeSchemaProbe(
                schema: resolved,
                tables: names.sorted(),
                messageTableHasRows: resolved.map { hasAnyRow(db, table: $0.messageTable) } ?? false
            )
        }
    }
}
