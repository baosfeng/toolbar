import Foundation

// MARK: - GitHub Copilot CLI 用量解析（SQLite `assistant_usage_events` 表）

/// Copilot CLI 用量解析器
///
/// 位置：`~/.copilot/session-store.db`（SQLite WAL，只读打开）。
/// 表 `assistant_usage_events`：**一次 API 请求一行**，带真实请求时间戳与缓存拆分，
/// 是这一家质量最高的输入 / 缓存来源。
///
/// 三条硬约束：
/// 1. **按列名取值，不按列序**：表结构随版本漂移，先用 `PRAGMA table_info` 拿列名，
///    再用候选列名逐个试（`input_tokens` / `cache_read_tokens` / `reasoning_tokens` …）；
/// 2. **`input_tokens` 是 cache-inclusive** → `uncachedInput = max(0, input - cacheRead)`；
/// 3. reasoning 视表内是否有独立列：有则**单列加进 output**，没有则视为已含在 output 里
///    （设计规格 §2.4 / §2.7）。
///
/// 本轮只接 CLI 的 SQLite；VS Code 的 delta journal（kind 0/1/2）不在范围内。
public enum CopilotUsageParser {
    public static let source: TokenSourceID = .copilot
    public static let databaseFileName = "session-store.db"
    public static let tableName = "assistant_usage_events"
    public static let unknownModel = "unknown"
    /// Copilot 的 provider 标识（表里没有 provider 列）
    public static let providerName = "github-copilot"

    /// 候选列名（按优先级；命中第一个可读值）
    enum Columns {
        static let input = ["input_tokens", "prompt_tokens", "inputTokens"]
        static let output = ["output_tokens", "completion_tokens", "outputTokens"]
        static let cacheRead = [
            "cache_read_tokens", "cache_read_input_tokens", "cached_input_tokens", "cacheReadTokens",
        ]
        static let cacheWrite = ["cache_write_tokens", "cache_creation_input_tokens", "cacheWriteTokens"]
        static let reasoning = ["reasoning_tokens", "reasoning_output_tokens", "reasoningTokens"]
        static let model = ["model", "model_id", "model_name", "modelID"]
        static let session = ["session_id", "sessionId", "conversation_id", "chat_session_id"]
        static let timestamp = [
            "created_at", "timestamp", "event_time", "occurred_at",
            "request_timestamp", "request_time", "time_created", "createdAt", "ts",
        ]
    }

    // MARK: - 纯函数入口

    /// 单行入口：一行「列名 → 值」→ 统一事件（永不抛错）
    ///
    /// - Parameter tableColumns: 该表实际拥有的列名集合。空集表示「不知道 schema」，
    ///   此时 reasoning 是否有独立列只能看本行有没有这个键。
    public static func parse(row: [String: Any], tableColumns: Set<String> = []) -> TokenSourceLineResult {
        // 没有输入列 → 不是用量行（表里可能混入其它事件）
        guard let input = intValue(row, Columns.input) else { return .ignored }
        guard let tsMs = timestampMilliseconds(row) else {
            return .malformed("用量行缺少可解析的时间戳")
        }
        let cacheRead = max(0, intValue(row, Columns.cacheRead) ?? 0)
        let cacheWrite = max(0, intValue(row, Columns.cacheWrite) ?? 0)
        let output = max(0, intValue(row, Columns.output) ?? 0)
        let usage = HarnessTokenUsage(
            uncachedInput: max(0, input - cacheRead),
            output: output + reasoningValue(row, tableColumns: tableColumns),
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            requestCount: 1
        )
        guard usage.totalTokens > 0 else { return .ignored }
        return .usage(TokenSourceUsageEvent(
            source: source,
            tsMs: tsMs,
            provider: providerName,
            model: stringValue(row, Columns.model) ?? unknownModel,
            usage: usage,
            sessionKey: stringValue(row, Columns.session) ?? "",
            cwd: ""
        ))
    }

    /// 整表入口（fixture 直接驱动）：若干行 → 与会话型解析器同形的报告
    public static func parse(
        rows: [[String: Any]],
        tableColumns: Set<String> = []
    ) -> TokenSourceParseReport {
        var events: [TokenSourceUsageEvent] = []
        var ignored = 0
        var malformed = 0
        for row in rows {
            switch parse(row: row, tableColumns: tableColumns) {
            case .usage(let event):
                events.append(event)
            case .session:
                ignored += 1
            case .ignored:
                ignored += 1
            case .malformed:
                malformed += 1
            }
        }
        // 「一次请求一行」，无累计 / 重放语义，故 skipped 恒为 0
        return TokenSourceParseReport(
            source: source,
            events: events,
            session: nil,
            ignoredLineCount: ignored,
            malformedLineCount: malformed,
            skippedLineCount: 0
        )
    }

    // MARK: - 数据库入口（只读）

    /// 给定 db 路径：整库读取 + 解析；不存在 / 打不开 / 缺表 → 空事件 + 降级原因（不抛）
    public static func read(databaseAt url: URL) -> TokenSourceSQLiteReadReport {
        read(databaseAt: url.path)
    }

    /// 给定 db 路径：整库读取 + 解析；不存在 / 打不开 / 缺表 → 空事件 + 降级原因（不抛）
    public static func read(databaseAt path: String) -> TokenSourceSQLiteReadReport {
        switch TokenSourceSQLiteAccess.openReadOnly(path: path) {
        case .failure(let reason):
            return .unavailable(source, reason)
        case .success(let db):
            defer { TokenSourceSQLiteAccess.close(db) }
            let columns = TokenSourceSQLiteAccess.columnNames(db, table: tableName)
            guard !columns.isEmpty else {
                // 坏文件的 `table_info` 同样是空结果：能读 sqlite_master 才是真的缺表
                if let message = TokenSourceSQLiteAccess.readError(db) {
                    return .unavailable(source, .openFailed(path: path, message: message))
                }
                return .unavailable(source, .tableMissing(table: tableName))
            }
            var rows: [[String: Any]] = []
            let readError = TokenSourceSQLiteAccess.forEachRow(db, sql: selectSQL(columns: columns)) { row in
                rows.append(row)
            }
            if let readError {
                return .unavailable(source, .openFailed(path: path, message: readError))
            }
            let report = parse(rows: rows, tableColumns: Set(columns))
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

    /// `SELECT *` + 能认出来的时间列排序（认不出来就不排序，绝不猜列名）
    private static func selectSQL(columns: [String]) -> String {
        let table = "SELECT * FROM " + tableName
        guard let timeColumn = Columns.timestamp.first(where: { columns.contains($0) }) else {
            return table + ";"
        }
        return table + " ORDER BY " + timeColumn + ";"
    }

    /// 时间列 → epoch 毫秒（兼容 ISO8601 文本、unix 秒、unix 毫秒）
    private static func timestampMilliseconds(_ row: [String: Any]) -> Int64? {
        for name in Columns.timestamp {
            guard let raw = row[name], !(raw is NSNull) else { continue }
            if let text = TokenSourceJSON.string(raw) {
                if let ms = TokenSourceJSON.milliseconds(fromISO8601: text) { return ms }
                if let number = Double(text) { return normalize(number) }
                continue
            }
            if let number = raw as? NSNumber { return normalize(number.doubleValue) }
            if let number = raw as? Double { return normalize(number) }
        }
        return nil
    }

    /// 秒 / 毫秒归一：低于 1e11 的整数按秒（1e11 毫秒 = 1973 年，秒口径到 5138 年才到）
    private static func normalize(_ value: Double) -> Int64? {
        guard value > 0 else { return nil }
        let rounded = Int64(value.rounded())
        return rounded < 100_000_000_000 ? rounded * 1000 : rounded
    }

    /// reasoning：表里有独立列才单列，否则视为已含在 output 里
    private static func reasoningValue(_ row: [String: Any], tableColumns: Set<String>) -> Int {
        if !tableColumns.isEmpty,
           !Columns.reasoning.contains(where: { tableColumns.contains($0) }) {
            return 0
        }
        return max(0, intValue(row, Columns.reasoning) ?? 0)
    }

    private static func intValue(_ row: [String: Any], _ candidates: [String]) -> Int? {
        for name in candidates {
            guard let value = row[name], !(value is NSNull) else { continue }
            if let number = TokenSourceJSON.int(value) { return number }
            if let number = value as? Double { return Int(number) }
        }
        return nil
    }

    private static func stringValue(_ row: [String: Any], _ candidates: [String]) -> String? {
        for name in candidates {
            if let text = TokenSourceJSON.string(row[name]) { return text }
        }
        return nil
    }
}
