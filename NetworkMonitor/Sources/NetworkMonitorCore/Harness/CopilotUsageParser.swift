import Foundation

// MARK: - GitHub Copilot CLI 用量解析（SQLite assistant_usage_events 表）

/// Copilot CLI 用量解析器
///
/// 位置：<COPILOT_HOME 或 ~/.copilot>/session-store.db（WAL，只读打开）。
/// 表 assistant_usage_events：**一次 API 请求一行**，带真实请求时间戳与缓存拆分。
///
/// 表结构来自官方 npm 产物 @github/copilot-darwin-arm64 内嵌 JS 的第一手 DDL：
///   id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, model TEXT NOT NULL,
///   input_tokens / output_tokens / cache_read_tokens / cache_write_tokens / reasoning_tokens INTEGER,
///   created_at TEXT DEFAULT (datetime('now')), event_id TEXT, UNIQUE(session_id, event_id)
///
/// 五条硬约束：
/// 1. **按列名取值、不按列序**：表结构随版本漂移，先 PRAGMA table_info 拿列名，再用候选列名逐个试；
/// 2. input_tokens 是 cache-inclusive → uncachedInput = max(0, input - cache_read)；
/// 3. reasoning_tokens 是**独立列**（上游与 output 分列，不像 OpenAI 的 completion_tokens 含
///    reasoning）→ **不并进 output**，四桶不含它；本解析器不采集该列，避免虚高；
/// 4. created_at 是 TEXT 且双来源：DEFAULT (datetime('now')) 写「YYYY-MM-DD HH:MM:SS」（空格、
///    无时区，**UTC**），显式绑定可能是 ISO8601 → 两种都吃；
/// 5. 去重镜像 UNIQUE(session_id, event_id) + ON CONFLICT DO NOTHING：按该键去重，event_id 为
///    NULL 的老行（SQLite 的 UNIQUE 允许重复 NULL）按行 id 兜底逐行保留。
///
/// 只读打开要兼容 CLI 同时持有 WAL：SQLITE_OPEN_READONLY + busy_timeout，**不**做 checkpoint、
/// 不写 -wal / -shm（见 TokenSourceSQLiteAccess）。
/// 只接 CLI 的 SQLite；VS Code 的 delta journal 不在范围内。
public enum CopilotUsageParser {
    public static let source: TokenSourceID = .copilot
    public static let databaseFileName = "session-store.db"
    public static let tableName = "assistant_usage_events"
    public static let unknownModel = "unknown"
    public static let providerName = "github-copilot"

    /// 候选列名（按优先级；命中第一个可读值）
    enum Columns {
        static let input = ["input_tokens", "prompt_tokens", "inputTokens"]
        static let output = ["output_tokens", "completion_tokens", "outputTokens"]
        static let cacheRead = [
            "cache_read_tokens", "cache_read_input_tokens", "cached_input_tokens", "cacheReadTokens",
        ]
        static let cacheWrite = ["cache_write_tokens", "cache_creation_input_tokens", "cacheWriteTokens"]
        static let model = ["model", "model_id", "model_name", "modelID"]
        static let session = ["session_id", "sessionId", "conversation_id", "chat_session_id"]
        static let timestamp = [
            "created_at", "timestamp", "event_time", "occurred_at",
            "request_timestamp", "request_time", "time_created", "createdAt", "ts",
        ]
        /// 去重键（UNIQUE(session_id, event_id)）
        static let eventID = ["event_id"]
        /// 行 id：DDL 的 id 或读取时取的 rowid 别名
        static let rowID = ["id", rowIDAlias]
        /// read() 里为 event_id 为 NULL 的老行额外取的 rowid 别名（`*` 不含 rowid）
        static let rowIDAlias = "nm_rowid"
    }

    // MARK: - 纯函数入口

    /// 单行入口：一行「列名 → 值」→ 统一事件（永不抛错）
    ///
    /// - Parameter tableColumns: 该表实际拥有的列名集合（保留给调用方传 schema；四桶映射已不再
    ///   依赖它 —— reasoning 无论有没有独立列都不并进 output）。
    public static func parse(row: [String: Any], tableColumns: Set<String> = []) -> TokenSourceLineResult {
        // 没有输入列 → 不是用量行（表里可能混入其它事件）
        guard let input = intValue(row, Columns.input) else { return .ignored }
        guard let tsMs = timestampMilliseconds(row) else {
            return .malformed("用量行缺少可解析的时间戳")
        }
        let cacheRead = max(0, intValue(row, Columns.cacheRead) ?? 0)
        let cacheWrite = max(0, intValue(row, Columns.cacheWrite) ?? 0)
        let output = max(0, intValue(row, Columns.output) ?? 0)
        // reasoning_tokens 刻意不加进 output：上游把两者分列，output_tokens 不含 reasoning
        let usage = HarnessTokenUsage(
            uncachedInput: max(0, input - cacheRead),
            output: output,
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
        var skipped = 0
        var seen = Set<String>()
        for (index, row) in rows.enumerated() {
            // UNIQUE(session_id, event_id) 的镜像：重复键只留一行（写入端本就 ON CONFLICT DO NOTHING）
            guard seen.insert(dedupeKey(row, rowIndex: index)).inserted else {
                skipped += 1
                continue
            }
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
                // 坏文件的 table_info 同样是空结果：能读 sqlite_master 才是真的缺表
                if let message = TokenSourceSQLiteAccess.readError(db) {
                    return .unavailable(source, .openFailed(path: path, message: message))
                }
                return .unavailable(source, .tableMissing(table: tableName))
            }
            var rows: [[String: Any]] = []
            var readError = TokenSourceSQLiteAccess.forEachRow(
                db, sql: selectSQL(columns: columns, withRowID: true)
            ) { rows.append($0) }
            if readError != nil {
                // WITHOUT ROWID 表没有 rowid：退一步不取别名再读一次（仍只读）
                rows.removeAll()
                readError = TokenSourceSQLiteAccess.forEachRow(
                    db, sql: selectSQL(columns: columns, withRowID: false)
                ) { rows.append($0) }
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

    /// 取行 + 能认出来的时间列排序（认不出来就不排序，绝不猜列名）
    ///
    /// `rowid AS nm_rowid, *`：`*` 不含 rowid，而 event_id 为 NULL 的老行需要它做去重兜底。
    private static func selectSQL(columns: [String], withRowID: Bool) -> String {
        var sql = withRowID
            ? "SELECT rowid AS " + Columns.rowIDAlias + ", * FROM " + tableName
            : "SELECT * FROM " + tableName
        if let timeColumn = Columns.timestamp.first(where: { columns.contains($0) }) {
            sql += " ORDER BY " + timeColumn
        }
        return sql + ";"
    }

    /// 去重键：镜像 UNIQUE(session_id, event_id)
    ///
    /// event_id 为 NULL 的老行按行 id（DDL 的 id / rowid 别名）兜底逐行保留；两者都取不到才退化到
    /// 行序号 —— 宁可多记一行，也不把两条真实请求静默合成一条。
    static func dedupeKey(_ row: [String: Any], rowIndex: Int) -> String {
        let session = stringValue(row, Columns.session) ?? ""
        if let event = valueText(row, Columns.eventID) { return session + "|e|" + event }
        if let rowID = valueText(row, Columns.rowID) { return session + "|r|" + rowID }
        return session + "|i|" + String(rowIndex)
    }

    /// 时间列 → epoch 毫秒（兼容 ISO8601 文本、datetime('now') 文本、unix 秒、unix 毫秒）
    private static func timestampMilliseconds(_ row: [String: Any]) -> Int64? {
        for name in Columns.timestamp {
            guard let raw = row[name], !(raw is NSNull) else { continue }
            if let text = TokenSourceJSON.string(raw) {
                if let ms = TokenSourceJSON.milliseconds(fromISO8601: text) { return ms }
                if let ms = milliseconds(fromUTCDateTime: text) { return ms }
                if let number = Double(text) { return normalize(number) }
                continue
            }
            if let number = raw as? NSNumber { return normalize(number.doubleValue) }
            if let number = raw as? Double { return normalize(number) }
        }
        return nil
    }

    /// 「YYYY-MM-DD HH:MM:SS[.fff]」（分隔符空格或 T）→ epoch 毫秒，无时区后缀按 **UTC** 解释
    ///
    /// 这是 SQLite `datetime('now')` 的默认输出形态（空格分隔、无时区、UTC），本机时区不是 UTC 时
    /// 用 DateFormatter 的本地时区会整体偏移，故显式按 UTC 组装。只接受 UTC 后缀（Z / +00:00），
    /// 其它偏移交给上面的 ISO8601 解析。
    static func milliseconds(fromUTCDateTime text: String) -> Int64? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19 else { return nil }
        func number(_ start: Int, _ length: Int) -> Int? {
            var value = 0
            for index in start..<(start + length) {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        let hyphen = UInt8(ascii: "-")
        let colon = UInt8(ascii: ":")
        let dot = UInt8(ascii: ".")
        guard bytes[4] == hyphen, bytes[7] == hyphen,
              bytes[10] == UInt8(ascii: " ") || bytes[10] == UInt8(ascii: "T"),
              bytes[13] == colon, bytes[16] == colon,
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 61
        else { return nil }
        var cursor = 19
        var fractionMilliseconds = 0
        if cursor < bytes.count, bytes[cursor] == dot {
            cursor += 1
            var scale = 100
            while cursor < bytes.count, scale > 0, bytes[cursor] >= 48, bytes[cursor] <= 57 {
                fractionMilliseconds += Int(bytes[cursor] - 48) * scale
                scale /= 10
                cursor += 1
            }
            while cursor < bytes.count, bytes[cursor] >= 48, bytes[cursor] <= 57 { cursor += 1 }
        }
        let suffix = text.dropFirst(cursor)
        guard suffix.isEmpty || suffix == "Z" || suffix == "z" || suffix == "+00:00" else {
            return nil
        }
        guard let epoch = utcMilliseconds(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ) else { return nil }
        return epoch + Int64(fractionMilliseconds)
    }

    /// 年月日时分秒（**UTC**）→ epoch 毫秒（公历 + UTC，不受本机时区影响）
    private static func utcMilliseconds(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    ) -> Int64? {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) { calendar.timeZone = utc }
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        guard let date = calendar.date(from: components) else { return nil }
        return TokenSourceJSON.milliseconds(from: date)
    }

    /// 秒 / 毫秒归一：低于 1e11 的整数按秒（1e11 毫秒 = 1973 年，秒口径到 5138 年才到）
    private static func normalize(_ value: Double) -> Int64? {
        guard value > 0 else { return nil }
        let rounded = Int64(value.rounded())
        return rounded < 100_000_000_000 ? rounded * 1000 : rounded
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

    /// 取文本形态（字符串原样；整数转十进制串）—— 去重键要用它读 event_id / id / rowid
    private static func valueText(_ row: [String: Any], _ candidates: [String]) -> String? {
        for name in candidates {
            if let text = TokenSourceJSON.string(row[name]) { return text }
            if let value = row[name], let number = TokenSourceJSON.int(value) { return String(number) }
        }
        return nil
    }
}
