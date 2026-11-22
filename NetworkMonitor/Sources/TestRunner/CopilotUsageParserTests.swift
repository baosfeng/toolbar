import Foundation
import NetworkMonitorCore

// MARK: - Copilot CLI 用量解析（设计规格 §2.4 / §7）
//
// 覆盖：`input - cache_read` 的 cache-inclusive 口径、reasoning 分列不并进 output、
// 无 reasoning 列时视为已含、三种时间形态（ISO8601 文本 / unix 秒 / unix 毫秒）、
// 非用量行归 ignored、缺时间归 malformed、整库只读读取、三种降级。
// 行 fixture 用「列名 → 值」字典自造，不依赖真实 session-store.db。

/// 表实际列名集合（含 reasoning_tokens；上游与 output 分列，故不并进 output）
private let copilotColumns: Set<String> = [
    "id", "created_at", "input_tokens", "output_tokens",
    "cache_read_tokens", "cache_write_tokens", "reasoning_tokens", "model", "session_id",
]

private nonisolated(unsafe) let copilotISO8601Row: [String: Any] = [
    "id": "evt-1",
    "input_tokens": 1200,
    "cache_read_tokens": 400,
    "cache_write_tokens": 30,
    "output_tokens": 500,
    "reasoning_tokens": 100,
    "model": "gpt-4.1",
    "session_id": "sess-1",
    "created_at": "2026-01-05T10:00:00.000Z",
]

private nonisolated(unsafe) let copilotUnixSecondsRow: [String: Any] = [
    "id": "evt-2",
    "input_tokens": 900,
    "cache_read_tokens": 300,
    "output_tokens": 200,
    "created_at": 1_767_585_600,
]

private nonisolated(unsafe) let copilotUnixMillisRow: [String: Any] = [
    "id": "evt-3",
    "input_tokens": 100,
    "output_tokens": 50,
    "created_at": 1_767_585_660_000,
]

/// 有输入列但没有任何可解析时间列 → malformed
private nonisolated(unsafe) let copilotMissingTimeRow: [String: Any] = [
    "id": "evt-bad",
    "input_tokens": 10,
    "output_tokens": 1,
]

func runCopilotUsageParserTests() {
    print("🧪 Testing Copilot 解析（input-cache / reasoning 列 / 三种时间 / 整库 / 降级）...")

    // MARK: 单行：cache-inclusive + reasoning 单列
    if case .usage(let first) = CopilotUsageParser.parse(row: copilotISO8601Row,
                                                        tableColumns: copilotColumns) {
        assertEqual(first.usage, HarnessTokenUsage(uncachedInput: 800, output: 500,
                                                   cacheRead: 400, cacheWrite: 30,
                                                   requestCount: 1),
                    "单行：input - cache_read = 800，output 500（reasoning 100 不进四桶）")
        assertEqual(first.source, TokenSourceID.copilot, "单行：来源标识")
        assertEqual(first.provider, "github-copilot", "单行：provider 常量")
        assertEqual(first.model, "gpt-4.1", "单行：模型列")
        assertEqual(first.sessionKey, "sess-1", "单行：会话列")
        assertEqual(first.tsMs, 1_767_607_200_000, "单行：ISO8601 文本时间 → epoch 毫秒")
    } else {
        assertEqual(false, true, "单行：ISO8601 行应解析为 usage")
    }

    // 无 reasoning 列：output 视为已含（不加 reasoning_tokens）
    let noReasoningColumns: Set<String> = ["input_tokens", "output_tokens", "created_at"]
    let noReasoningRow: [String: Any] = [
        "input_tokens": 800, "output_tokens": 700, "reasoning_tokens": 100,
        "created_at": 1_767_585_600,
    ]
    if case .usage(let folded) = CopilotUsageParser.parse(row: noReasoningRow,
                                                          tableColumns: noReasoningColumns) {
        assertEqual(folded.usage.output, 700, "无 reasoning 列：output 原样")
        assertEqual(folded.usage.uncachedInput, 800, "无 reasoning 列：uncached 照常")
    } else {
        assertEqual(false, true, "无 reasoning 列：应解析为 usage")
    }
    // 同样一行但表里确有 reasoning 列 → 仍不相加（上游 output 不含 reasoning）
    if case .usage(let separated) = CopilotUsageParser.parse(row: noReasoningRow,
                                                             tableColumns: copilotColumns) {
        assertEqual(separated.usage.output, 700, "有 reasoning 列：不并进 output")
    } else {
        assertEqual(false, true, "有 reasoning 列：应解析为 usage")
    }

    // cache_read 大于 input 时 uncached 夹到 0
    if case .usage(let clamped) = CopilotUsageParser.parse(
        row: ["input_tokens": 100, "cache_read_tokens": 300, "output_tokens": 10,
              "created_at": 1_767_585_600], tableColumns: copilotColumns) {
        assertEqual(clamped.usage.uncachedInput, 0, "边界：cache_read > input 时 uncached 夹到 0")
        assertEqual(clamped.usage.cacheRead, 300, "边界：cacheRead 原样")
    } else {
        assertEqual(false, true, "边界：cache_read > input 应解析为 usage")
    }

    // MARK: 整表入口：三行 + 一行缺时间
    let rows: [[String: Any]] = [copilotISO8601Row, copilotUnixSecondsRow,
                                 copilotUnixMillisRow, copilotMissingTimeRow]
    let report = CopilotUsageParser.parse(rows: rows, tableColumns: copilotColumns)
    assertEqual(report.source, TokenSourceID.copilot, "整表：来源标识")
    assertEqual(report.events.count, 3, "整表：三行用量行")
    assertEqual(report.usage, HarnessTokenUsage(uncachedInput: 1500, output: 750,
                                                cacheRead: 700, cacheWrite: 30, requestCount: 3),
                "整表：四桶合计 1500 / 750 / 700 / 30")
    assertEqual(report.requestCount, 3, "整表：requests=3")
    assertEqual(report.malformedLineCount, 1, "整表：缺时间行记 malformed")
    assertEqual(report.ignoredLineCount, 0, "整表：无 ignored")
    assertEqual(report.skippedLineCount, 0, "整表：一次请求一行，无 skipped")
    assertEqual(report.events.map(\.usage),
                [HarnessTokenUsage(uncachedInput: 800, output: 500, cacheRead: 400,
                                   cacheWrite: 30, requestCount: 1),
                 HarnessTokenUsage(uncachedInput: 600, output: 200, cacheRead: 300,
                                   cacheWrite: 0, requestCount: 1),
                 HarnessTokenUsage(uncachedInput: 100, output: 50, cacheRead: 0,
                                   cacheWrite: 0, requestCount: 1)],
                "整表：三行分别为 [800,500,400,30] / [600,200,300,0] / [100,50,0,0]")
    assertEqual(report.events.map(\.tsMs),
                [1_767_607_200_000, 1_767_585_600_000, 1_767_585_660_000],
                "整表：ISO8601 / unix 秒 / unix 毫秒三种时间形态都归一为毫秒")

    // 非用量行（没有输入列）→ ignored
    if case .ignored = CopilotUsageParser.parse(row: ["kind": "session_start"],
                                                tableColumns: copilotColumns) {
        assertEqual(true, true, "分类：没有输入列的行归 ignored")
    } else {
        assertEqual("ignored", "非 ignored", "分类：非用量行应归 ignored")
    }

    // MARK: 整库读取
    let dbPath = tokenSourceTempDatabasePath("copilot")
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    func valueLiteral(_ key: String, _ row: [String: Any]) -> String {
        if let text = row[key] as? String { return tokenSourceTextLiteral(text) }
        if let number = row[key] as? Int { return String(number) }
        return "NULL"
    }
    let insertRows = [copilotISO8601Row, copilotUnixSecondsRow, copilotUnixMillisRow]
        .map { row in
            "(" + valueLiteral("id", row) + ", " + valueLiteral("created_at", row) + ", "
                + valueLiteral("input_tokens", row) + ", " + valueLiteral("output_tokens", row) + ", "
                + valueLiteral("cache_read_tokens", row) + ", " + valueLiteral("cache_write_tokens", row)
                + ", " + valueLiteral("reasoning_tokens", row) + ", " + valueLiteral("model", row) + ", "
                + valueLiteral("session_id", row) + ")"
        }
        .joined(separator: ", ")
    guard tokenSourceMakeSQLite(at: dbPath, statements: [
        "CREATE TABLE assistant_usage_events (id TEXT, created_at TEXT, input_tokens INTEGER, "
            + "output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, "
            + "reasoning_tokens INTEGER, model TEXT, session_id TEXT);",
        "INSERT INTO assistant_usage_events (id, created_at, input_tokens, output_tokens, "
            + "cache_read_tokens, cache_write_tokens, reasoning_tokens, model, session_id) VALUES "
            + insertRows + ";",
    ]) else {
        assertEqual(false, true, "整库：fixture 建库失败")
        return
    }
    let read = CopilotUsageParser.read(databaseAt: dbPath)
    assertEqual(read.isAvailable, true, "整库：可读")
    assertEqual(read.events.count, 3, "整库：三行事件")
    assertEqual(read.usage, HarnessTokenUsage(uncachedInput: 1500, output: 750,
                                              cacheRead: 700, cacheWrite: 30, requestCount: 3),
                "整库：四桶与请求数与整表入口一致")
    assertEqual(read.malformedRowCount, 0, "整库：三行都合法")

    // MARK: 降级：库不存在 / 非 SQLite / 缺表
    let missing = CopilotUsageParser.read(databaseAt: tokenSourceTempDatabasePath("copilot-missing"))
    assertEqual(missing.isAvailable, false, "降级：库不存在 → available=false")
    assertEqual(missing.events.count, 0, "降级：库不存在 → 零事件")
    assertEqual(missing.usage, HarnessTokenUsage.zero, "降级：库不存在 → 四桶全 0")
    assertEqual(missing.unavailable?.displayMessage.isEmpty == false, true, "降级：库不存在带原因文案")

    let garbagePath = tokenSourceTempDatabasePath("copilot-garbage")
    defer { try? FileManager.default.removeItem(atPath: garbagePath) }
    _ = FileManager.default.createFile(atPath: garbagePath, contents: Data("not a sqlite database".utf8))
    let garbage = CopilotUsageParser.read(databaseAt: garbagePath)
    assertEqual(garbage.isAvailable, false, "降级：非 SQLite 文件 → available=false")
    assertEqual(garbage.events.count, 0, "降级：非 SQLite 文件 → 零事件")
    assertEqual(garbage.unavailable?.displayMessage.isEmpty == false, true, "降级：非 SQLite 文件带原因文案")

    let tableMissingPath = tokenSourceTempDatabasePath("copilot-notable")
    defer { try? FileManager.default.removeItem(atPath: tableMissingPath) }
    _ = tokenSourceMakeSQLite(at: tableMissingPath, statements: ["CREATE TABLE other (id TEXT);"])
    let noTable = CopilotUsageParser.read(databaseAt: tableMissingPath)
    assertEqual(noTable.isAvailable, false, "降级：缺 assistant_usage_events 表 → available=false")
    if case .tableMissing(let table)? = noTable.unavailable {
        assertEqual(table, "assistant_usage_events", "降级：缺表原因指出表名")
    } else {
        assertEqual("tableMissing", String(describing: noTable.unavailable), "降级：缺表原因分类")
    }

    // MARK: 新场景 1：datetime('now') 文本时间（空格分隔、无时区 → 按 UTC 解释）
    if case .usage(let sqliteText) = CopilotUsageParser.parse(
        row: ["session_id": "s-2", "event_id": "ev-9", "model": "gpt-5",
              "input_tokens": 1000, "cache_read_tokens": 200, "output_tokens": 100,
              "created_at": "2026-11-22 06:12:00"],
        tableColumns: copilotColumns) {
        assertEqual(sqliteText.tsMs, 1_795_327_920_000, "时间：datetime('now') 文本按 UTC 解释")
        assertEqual(sqliteText.usage, HarnessTokenUsage(uncachedInput: 800, output: 100,
                                                       cacheRead: 200, cacheWrite: 0, requestCount: 1),
                    "时间：uncached 800 / output 100 / cacheRead 200")
    } else {
        assertEqual(false, true, "时间：datetime('now') 文本应解析为 usage")
    }

    // MARK: 新场景 2：(session_id, event_id) 去重；event_id 为 NULL 的老行按行 id 兜底
    let dedupeRows: [[String: Any]] = [
        ["session_id": "s-3", "event_id": "dup", "input_tokens": 100, "output_tokens": 10,
         "created_at": "2026-11-22 06:12:00"],
        ["session_id": "s-3", "event_id": "dup", "input_tokens": 100, "output_tokens": 10,
         "created_at": "2026-11-22 06:12:00"],
        ["session_id": "s-4", "event_id": "dup", "input_tokens": 50, "output_tokens": 5,
         "created_at": "2026-11-22 06:12:00"],
        ["session_id": "s-5", "event_id": NSNull(), "id": 41, "input_tokens": 30,
         "output_tokens": 3, "created_at": "2026-11-22 06:12:00"],
        ["session_id": "s-5", "event_id": NSNull(), "id": 42, "input_tokens": 30,
         "output_tokens": 3, "created_at": "2026-11-22 06:12:00"],
    ]
    let dedupe = CopilotUsageParser.parse(rows: dedupeRows)
    assertEqual(dedupe.events.count, 4, "去重：同键合并后 4 行（NULL event_id 按行 id 各留一条）")
    assertEqual(dedupe.skippedLineCount, 1, "去重：重复键计 skipped=1")
    assertEqual(dedupe.usage.uncachedInput, 210, "去重：uncached 100+50+30+30=210")

    // MARK: 新场景 3：整库路径同样去重（rowid 别名兜底 NULL event_id；DEFAULT datetime('now'))
    let dedupePath = tokenSourceTempDatabasePath("copilot-dedupe")
    defer { try? FileManager.default.removeItem(atPath: dedupePath) }
    if tokenSourceMakeSQLite(at: dedupePath, statements: [
        "CREATE TABLE assistant_usage_events (id INTEGER PRIMARY KEY AUTOINCREMENT, "
            + "session_id TEXT, event_id TEXT, model TEXT, input_tokens INTEGER, "
            + "output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, "
            + "reasoning_tokens INTEGER, created_at TEXT DEFAULT (datetime('now')));",
        "INSERT INTO assistant_usage_events (session_id, event_id, input_tokens, output_tokens) "
            + "VALUES ('s-6','dup',100,10), ('s-6','dup',100,10), ('s-6',NULL,40,4), ('s-6',NULL,40,4);",
    ]) {
        let dedupeRead = CopilotUsageParser.read(databaseAt: dedupePath)
        assertEqual(dedupeRead.events.count, 3,
                    "整库去重：同 event_id 只留一条，NULL event_id 两行按 rowid 各留")
        assertEqual(dedupeRead.skippedRowCount, 1, "整库去重：重复计 skipped=1")
        assertEqual(dedupeRead.malformedRowCount, 0, "整库去重：DEFAULT datetime('now') 全部可解析")
    } else {
        assertEqual(false, true, "整库去重：fixture 建库失败")
    }

    // MARK: 新场景 4：COPILOT_HOME 优先，其次 ~/.copilot
    let envRoots = TokenSourceID.copilot.defaultRoots(
        homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
        environment: ["COPILOT_HOME": "/tmp/copilot-home"])
    assertEqual(envRoots.map(\.path), ["/tmp/copilot-home/session-store.db"],
                "路径：COPILOT_HOME 生效")
    let plainRoots = TokenSourceID.copilot.defaultRoots(
        homeDirectory: URL(fileURLWithPath: "/Users/fixture"), environment: [:])
    assertEqual(plainRoots.map(\.path), ["/Users/fixture/.copilot/session-store.db"],
                "路径：无环境变量回落 ~/.copilot")
    assertEqual(TokenSourceID.copilot.environmentKey, "COPILOT_HOME", "路径：环境变量键")

    print("✅ Copilot 解析 works")
}
