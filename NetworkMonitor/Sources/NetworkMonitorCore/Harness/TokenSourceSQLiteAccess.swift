import Foundation
import SQLite3

// MARK: - SQLite 来源的只读访问

/// SQLite 来源（OpenCode / Copilot CLI）的降级原因
///
/// 与 JSONL 的「坏行」不同：库打不开是**整源不可用**，事件为空但原因要能报到诊断里，
/// 故单列枚举，不混进 malformed 计数。
public enum TokenSourceSQLiteUnavailableReason: Error, Sendable, Equatable {
    /// 库文件不存在（没装，或 CLI 还没写过）
    case fileMissing(path: String)
    /// 打不开（权限 / 卷未挂载 / 不是 SQLite 库）
    case openFailed(path: String, message: String)
    /// 库里没有约定的表（版本漂移，或指错了库）
    case tableMissing(table: String)

    /// 诊断文案（路径是否脱敏由调用方按既有口径处理）
    public var displayMessage: String {
        switch self {
        case .fileMissing(let path): return "数据库不存在：" + path
        case .openFailed(let path, let message): return "数据库打开失败：" + path + "（" + message + "）"
        case .tableMissing(let table):
            // 「缺表」是内部术语：说清是库结构与预期不符（版本差异 / 指错了库）
            return "数据库里没有预期的表结构（工具版本可能不同）：" + table
        }
    }
}

/// SQLite 来源的整库读取结果：事件 + 降级原因
///
/// `unavailable == nil` 表示正常读到（哪怕 0 行）；非 nil 时事件必为空。
public struct TokenSourceSQLiteReadReport: Sendable, Equatable {
    public let source: TokenSourceID
    public let events: [TokenSourceUsageEvent]
    public let ignoredRowCount: Int
    public let malformedRowCount: Int
    public let skippedRowCount: Int
    public let unavailable: TokenSourceSQLiteUnavailableReason?

    public init(
        source: TokenSourceID,
        events: [TokenSourceUsageEvent],
        ignoredRowCount: Int = 0,
        malformedRowCount: Int = 0,
        skippedRowCount: Int = 0,
        unavailable: TokenSourceSQLiteUnavailableReason? = nil
    ) {
        self.source = source
        self.events = events
        self.ignoredRowCount = ignoredRowCount
        self.malformedRowCount = malformedRowCount
        self.skippedRowCount = skippedRowCount
        self.unavailable = unavailable
    }

    /// 降级结果（空事件 + 原因）
    public static func unavailable(
        _ source: TokenSourceID,
        _ reason: TokenSourceSQLiteUnavailableReason
    ) -> TokenSourceSQLiteReadReport {
        TokenSourceSQLiteReadReport(source: source, events: [], unavailable: reason)
    }

    public var isAvailable: Bool { unavailable == nil }

    /// 四桶合计
    public var usage: HarnessTokenUsage {
        events.reduce(HarnessTokenUsage.zero) { $0.adding($1.usage) }
    }

    public var requestCount: Int {
        events.reduce(0) { $0 + $1.usage.requestCount }
    }

    /// 与 JSONL 来源同形的报告（这两个来源的 cwd 来自 session 表，故 session 恒为 nil）
    public var parseReport: TokenSourceParseReport {
        TokenSourceParseReport(
            source: source,
            events: events,
            session: nil,
            ignoredLineCount: ignoredRowCount,
            malformedLineCount: malformedRowCount,
            skippedLineCount: skippedRowCount
        )
    }
}

/// SQLite 来源共用的只读访问（只做打开 / 读列名 / 逐行取值，**不写任何东西**）
///
/// 只读是硬约束：OpenCode / Copilot 的 CLI 可能正持有同一份 WAL 库，
/// 我们不建表、不 checkpoint、不写 -journal、不写 -wal。
/// 本路径没有 SQL 参数绑定（表名来自代码常量）；需要绑定时按 `SQLitePrimitives` 的口径
/// （一律 SQLITE_TRANSIENT，见 `DatabaseManager.sqlite3_bind_text_copy`）。
enum TokenSourceSQLiteAccess {

    /// 只读打开：`SQLITE_OPEN_READONLY` + `PRAGMA query_only`
    static func openReadOnly(path: String) -> Result<OpaquePointer, TokenSourceSQLiteUnavailableReason> {
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(.fileMissing(path: path))
        }
        var conn: OpaquePointer?
        let status = path.withCString { sqlite3_open_v2($0, &conn, SQLITE_OPEN_READONLY, nil) }
        guard status == SQLITE_OK, let conn else {
            let message = conn.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 返回 " + String(status)
            if let conn { sqlite3_close(conn) }
            return .failure(.openFailed(path: path, message: message))
        }
        // 库被 CLI 占着时短暂忙等，而不是立刻判失败（WAL 下只读读的是最新已提交快照）
        sqlite3_busy_timeout(conn, 2000)
        _ = sqlite3_exec(conn, "PRAGMA query_only = 1;", nil, nil, nil)
        return .success(conn)
    }

    /// 表的列名（按声明顺序）；表不存在返回空数组
    static func columnNames(_ db: OpaquePointer, table: String) -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(" + table + ");", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cName = sqlite3_column_text(stmt, 1) { names.append(String(cString: cName)) }
        }
        return names
    }

    /// 库本身能读吗（区分「不是 SQLite 库」与「缺表」：坏文件的 `table_info` 也是空结果）
    ///
    /// - Returns: nil = 库可读；非 nil = 读 `sqlite_master` 失败的原因
    static func readError(_ db: OpaquePointer) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master;", -1, &stmt, nil) == SQLITE_OK else {
            return String(cString: sqlite3_errmsg(db))
        }
        return sqlite3_step(stmt) == SQLITE_ROW ? nil : String(cString: sqlite3_errmsg(db))
    }

    /// 逐行把「列名 → 值」交给回调；返回 nil = 读完，非 nil = 读取失败原因
    ///
    /// 值只有 NSString / NSNumber / Data / NSNull 四种，调用方用 `TokenSourceJSON`
    /// 的宽松读取处理缺失与类型不符（与 JSONL 来源同一口径）。
    static func forEachRow(
        _ db: OpaquePointer,
        sql: String,
        _ body: ([String: Any]) -> Void
    ) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return String(cString: sqlite3_errmsg(db))
        }
        defer { sqlite3_finalize(stmt) }
        let columnCount = sqlite3_column_count(stmt)
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return nil }
            guard step == SQLITE_ROW else { return String(cString: sqlite3_errmsg(db)) }
            var row: [String: Any] = [:]
            for index in 0..<columnCount {
                guard let cName = sqlite3_column_name(stmt, index) else { continue }
                row[String(cString: cName)] = value(stmt, index: index)
            }
            body(row)
        }
    }

    /// 关闭连接（只读连接无待提交事务，直接 close）
    static func close(_ db: OpaquePointer) {
        sqlite3_close(db)
    }

    /// 单列取值（按 SQLite 存储类型转成 Foundation 对象）
    private static func value(_ stmt: OpaquePointer?, index: Int32) -> Any {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            return NSNumber(value: sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return NSNumber(value: sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            guard let cText = sqlite3_column_text(stmt, index) else { return NSNull() }
            return String(cString: cText) as NSString
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(stmt, index) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, index)))
        default:
            return NSNull()
        }
    }
}
