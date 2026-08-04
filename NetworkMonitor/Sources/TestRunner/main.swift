import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - Assertion Helpers

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ \(expected)", message.isEmpty ? "" : " — \(message)")
    } else {
        print("❌ \(file):\(line) — expected \"\(expected)\", got \"\(actual)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        print("✅ \(message.isEmpty ? "not nil" : message)")
    } else {
        print("❌ \(file):\(line) — expected not nil\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

// MARK: - Test formatSpeedShort

let speedCases: [(bps: Double, expected: String)] = [
    (0.0, "0B"),
    (500.0, "500B"),
    (1_500.0, "2K"),
    (42_000.0, "42K"),
    (999_000.0, "999K"),
    (1_200_000.0, "1.2M"),
    (55_000_000.0, "55.0M"),
    (2_300_000_000.0, "2.3G"),
]
print("🧪 Testing formatSpeedShort...")
for (bps, expected) in speedCases {
    assertEqual(formatSpeedShort(bps), expected)
}

// MARK: - Test parseNettopLine

print("\n🧪 Testing parseNettopLine...")

let line1 = "23:46:47.674162 Google Chrome H.51129                                   16218            4096"
let r1 = parseNettopLine(line1)
assertNotNil(r1, "should parse normal line")
if let r = r1 {
    assertEqual(r.name, "Google Chrome H", "name")
    assertEqual(r.pid, Int32(51129), "pid")
    assertEqual(r.bytesIn, UInt64(16218), "bytesIn")
    assertEqual(r.bytesOut, UInt64(4096), "bytesOut")
}

let lineMulti = "23:46:48.123456 Microsoft Excel T.12345                                   98765           43210"
let rMulti = parseNettopLine(lineMulti)
assertNotNil(rMulti, "multi-word name")
if let r = rMulti {
    assertEqual(r.name, "Microsoft Excel T", "multi-word name")
    assertEqual(r.pid, Int32(12345), "multi-word pid")
    assertEqual(r.bytesIn, UInt64(98765), "multi-word bytesIn")
}

let line2 = "23:46:47.674152 airportd.649                                                                                   0               0"
let r2 = parseNettopLine(line2)
assertNotNil(r2, "should parse zero line")
if let r = r2 {
    assertEqual(r.name, "airportd")
    assertEqual(r.bytesIn, UInt64(0))
}

let line3 = "23:46:47.674157 mDNSResponder.689                                                                  105434952       59651139"
let r3 = parseNettopLine(line3)
assertNotNil(r3, "should parse large numbers")
if let r = r3 {
    assertEqual(r.bytesIn, UInt64(105434952))
    assertEqual(r.bytesOut, UInt64(59651139))
}

let header = parseNettopLine("time                                                                            interface   type        bytes_in       bytes_out   rcvsize  tc_class arch")
assertEqual(header, nil, "header should return nil")

let empty = parseNettopLine("")
assertEqual(empty, nil, "empty should return nil")

// MARK: - Test sparkline

print("\n🧪 Testing sparkline...")

assertEqual(sparkline(from: []), "", "empty")

let allSame = sparkline(from: [0, 0, 0])
assertEqual(allSame, "▁▁▁", "all zero")

let linear = sparkline(from: [0, 1, 2, 3, 4, 5, 6, 7])
assertEqual(linear, "▁▂▃▄▅▆▇█", "linear 0-7")

let single = sparkline(from: [42])
assertEqual(single, "█", "single peak")

let desc = sparkline(from: [5, 4, 3, 2, 1, 0])
assertEqual(desc, "█▆▅▃▂▁", "descending")

// MARK: - Test formatBytesFull

print("\n🧪 Testing formatBytesFull...")
assertEqual(formatBytesFull(0), "Zero KB")
assertEqual(formatBytesFull(1024), "1 KB")
assertEqual(formatBytesFull(1_000_000), "1 MB")
assertEqual(formatBytesFull(2_500_000_000), "2.5 GB")

// MARK: - Test SessionSidecarData.parseTelemetry（上游平铺格式）

print("\n🧪 Testing SessionSidecarData.parseTelemetry...")

do {
    // 上游 desktop sessionUsageStats 平铺格式（顶层直接是字段）
    let flatJSON = """
    {"promptTokens":100,"completionTokens":50,"totalTokens":150,"reasoningTokens":30,
     "cacheHitTokens":80,"cacheMissTokens":20,"requestCount":3,"elapsedMs":1200,
     "sessionCost":0.05,"sessionCurrency":"USD","sessionCostUsd":0.05}
    """
    let data = SessionSidecarData.parseTelemetry(Data(flatJSON.utf8))
    assertEqual(data.promptTokens, 100, "flat prompt tokens")
    assertEqual(data.completionTokens, 50, "flat completion tokens")
    assertEqual(data.totalTokens, 150, "flat total tokens")
    assertEqual(data.reasoningTokens, 30, "flat reasoning tokens")
    assertEqual(data.cost, 0.05, "flat cost uses sessionCostUsd")

    print("✅ parseTelemetry 平铺格式 works")
}

do {
    // 上游平铺格式 + snake_case 字段名
    let snakeJSON = """
    {"prompt_tokens":200,"completion_tokens":100,"total_tokens":300,"reasoning_tokens":50,
     "session_cost":0.1,"session_currency":"USD"}
    """
    let data = SessionSidecarData.parseTelemetry(Data(snakeJSON.utf8))
    assertEqual(data.totalTokens, 300, "snake_case total tokens")
    assertEqual(data.promptTokens, 200, "snake_case prompt tokens")
    assertEqual(data.cost, 0.1, "snake_case cost")

    print("✅ parseTelemetry snake_case works")
}

do {
    // 货币归一：sessionCurrency=CNY 且无 sessionCostUsd → 按汇率反算 USD
    let cnyJSON = """
    {"totalTokens":400,"sessionCost":7.2,"sessionCurrency":"CNY"}
    """
    let data = SessionSidecarData.parseTelemetry(Data(cnyJSON.utf8))
    assertEqual(data.totalTokens, 400, "CNY case total tokens")
    assertEqual(data.cost, 1.0, "CNY cost converted back to USD (7.2/7.2)")

    print("✅ parseTelemetry CNY 货币归一 works")
}

do {
    // 旧版 usage 嵌套对象格式仍兼容
    let legacyJSON = """
    {"event":"Stop","sessionId":"sess-old","usage":{"promptTokens":50,"completionTokens":50,"totalTokens":100,"cost":0.02}}
    """
    let data = SessionSidecarData.parseTelemetry(Data(legacyJSON.utf8))
    assertEqual(data.totalTokens, 100, "legacy nested usage total tokens")
    assertEqual(data.cost, 0.02, "legacy nested usage cost")

    print("✅ parseTelemetry 旧版嵌套格式 works")
}

do {
    // 空/坏数据 → 全 0
    let empty = SessionSidecarData.parseTelemetry(Data("not json".utf8))
    assertEqual(empty.totalTokens, 0, "bad json yields zeros")
    assertEqual(empty.cost, 0.0, "bad json cost zero")

    print("✅ parseTelemetry 坏数据容错 works")
}

// MARK: - Test ReasonixStatsLoader（官方 stats JSONL）

print("\n🧪 Testing ReasonixStatsLoader...")

do {
    let dir = NSTemporaryDirectory() + "stats-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    // 与上游 stats.record 完全一致的 JSON 行
    let day = "2026-08-03"
    let lines = """
    {"ts":"2026-08-03T10:00:00+08:00","model":"deepseek/deepseek-v4-flash","source":"desktop","prompt":100,"completion":50,"reasoning":20,"cache_hit":80,"cache_miss":70,"total":150}
    {"ts":"2026-08-03T10:05:00+08:00","model":"deepseek/deepseek-v4-pro","source":"cli","prompt":200,"completion":100,"total":300}
    {"ts":"2026-08-03T10:06:00+08:00","source":"desktop","turn":true}
    {"ts":"2026-08-03T10:07:00+08:00","total":        // torn line（崩溃残留）应跳过
    """
    try! lines.write(toFile: "\(dir)/\(day).jsonl", atomically: true, encoding: .utf8)

    let records = ReasonixStatsLoader.loadAll(statsDir: dir)
    assertEqual(records.count, 3, "3 valid records, torn line skipped")

    let total = ReasonixStatsLoader.totalTokens(statsDir: dir)
    assertEqual(total, 450, "total excludes turn marker (150+300)")

    if records.count >= 1 {
        assertEqual(records[0].model, "deepseek/deepseek-v4-flash", "model parsed")
        assertEqual(records[0].cacheHitTokens, 80, "cache_hit parsed")
        assertEqual(records[0].cacheMissTokens, 70, "cache_miss parsed")
        assertEqual(records[2].isTurn, true, "turn marker parsed")
    }

    print("✅ ReasonixStatsLoader works")
}

do {
    // 目录不存在 → 空结果不崩溃
    let total = ReasonixStatsLoader.totalTokens(statsDir: "/nonexistent/stats-dir")
    assertEqual(total, 0, "missing dir yields 0")

    print("✅ ReasonixStatsLoader 空目录容错 works")
}

// MARK: - Test ReasonixPath.workspaceSlug（对齐上游 config.WorkspaceSlug）

print("\n🧪 Testing ReasonixPath.workspaceSlug...")

do {
    let slug = ReasonixPath.workspaceSlug(cwd: "<repo>")
    assertEqual(slug, "-Users-bsfeng-IdeaProjects-toolbar", "slashes replaced with dashes")
}

do {
    // 反斜杠与冒号同样替换（Windows 风格路径）
    let slug = ReasonixPath.workspaceSlug(cwd: "C:\\Users\\dev\\project")
    assertEqual(slug, "C--Users-dev-project", "backslash and colon replaced")
}

do {
    // 超长路径：截断到 255 字节 + FNV-1a 16 位 hex 后缀
    let long = String(repeating: "a", count: 300)
    let slug = ReasonixPath.workspaceSlug(cwd: long)
    assertEqual(slug.utf8.count, 255, "slug capped at 255 bytes")
    assertEqual(slug.hasSuffix("-\(String(format: "%016x", ReasonixPath.fnv1a64(long)))"), true, "hash suffix appended")

    print("✅ workspaceSlug 超长路径截断 works")
}

// MARK: - Test DatabaseManager (in-memory)
// MARK: - Test ReasonixHookEvent JSON 解析

print("\n🧪 Testing ReasonixHookEvent JSON 解析...")

let validJSON = """
{"event":"SessionStart","sessionId":"sess-123","project":"toolbar","model":"gpt-5","topic":"测试","turns":1,"timestamp":"2026-08-03T10:00:00.000Z","usage":{"promptTokens":100,"completionTokens":50,"totalTokens":150,"cost":0.01}}
"""

if let parsed = try? ReasonixHookEvent.from(jsonData: Data(validJSON.utf8)) {
    assertEqual(parsed.eventType, .sessionStart, "event type")
    assertEqual(parsed.sessionId, "sess-123", "session id")
    assertEqual(parsed.totalTokens, 150, "total tokens")
    assertEqual(parsed.turns, 1, "turns")
    assertEqual(parsed.cost, 0.01, "cost")
} else {
    print("❌ valid JSON should parse")
    exit(1)
}

// snake_case 兼容
let snakeJSON = """
{"event":"Stop","sessionId":"sess-456","usage":{"total_tokens":200,"prompt_tokens":100,"completion_tokens":100,"cost":0.02}}
"""
if let snake = try? ReasonixHookEvent.from(jsonData: Data(snakeJSON.utf8)) {
    assertEqual(snake.eventType, .stop, "snake_case event type")
    assertEqual(snake.totalTokens, 200, "total tokens from snake_case")
    assertEqual(snake.cost, 0.02, "cost from snake_case")
} else {
    print("❌ snake_case JSON should parse")
    exit(1)
}

// 缺少 event 字段 → 抛错
do {
    _ = try ReasonixHookEvent.from(jsonData: Data("{\"sessionId\":\"sess\"}".utf8))
    print("❌ should throw for missing event field")
    exit(1)
} catch let err as ReasonixHookError {
    assertEqual(err.localizedDescription.contains("event"), true, "missing field error")
}

// MARK: - Test DatabaseManager (in-memory)

print("\n🧪 Testing DatabaseManager...")

// Helper: run query on DatabaseManager and collect results as rows of [String?]
func collectQuery(_ db: DatabaseManager, sql: String) -> [[String?]] {
    var rows: [[String?]] = []
    db.query(sql: sql) { stmt in
        var row: [String?] = []
        let colCount = sqlite3_column_count(stmt)
        for i in 0..<colCount {
            if sqlite3_column_type(stmt, i) == SQLITE_NULL {
                row.append(nil)
            } else if let cStr = sqlite3_column_text(stmt, i) {
                row.append(String(cString: cStr))
            } else {
                row.append(nil)
            }
        }
        rows.append(row)
    }
    return rows
}

/// 同步等待：serialQueue 上的 async 写入会排在 sync query 之前完成
func drainQueue(_ db: DatabaseManager) {
    db.query(sql: "SELECT 1") { _ in }
}

// Test: hook 表自动创建 + writeHookEvent 写入
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    assertEqual(db.isReady, true, "in-memory db should be ready")

    let tables = collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('hook_events','hook_sessions','hook_tool_calls') ORDER BY name")
    assertEqual(tables.count, 3, "hook tables should be created")

    let event = try! ReasonixHookEvent.from(jsonData: Data(validJSON.utf8))
    db.writeHookEvent(event: event)
    drainQueue(db)

    let rows = collectQuery(db, sql: "SELECT session_id, event_type, total_tokens FROM hook_events")
    assertEqual(rows.count, 1, "should have 1 hook event")
    if rows.count >= 1 {
        assertEqual(rows[0][0], "sess-123", "session id")
        assertEqual(rows[0][1], "SessionStart", "event type")
        assertEqual(rows[0][2], "150", "total tokens")
    }

    print("✅ writeHookEvent works")
}

// Test: upsertHookSession — SessionStart 创建，Stop 更新为累计最大值
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let start = try! ReasonixHookEvent.from(jsonData: Data(validJSON.utf8))
    db.upsertHookSession(event: start)
    drainQueue(db)

    var rows = collectQuery(db, sql: "SELECT status, total_tokens FROM hook_sessions WHERE session_id='sess-123'")
    assertEqual(rows.count, 1, "session should be created")
    if rows.count >= 1 {
        assertEqual(rows[0][0], "active", "initial status active")
        assertEqual(rows[0][1], "150", "initial total tokens")
    }

    let stopJSON = """
    {"event":"Stop","sessionId":"sess-123","turns":2,"timestamp":"2026-08-03T10:01:00.000Z","usage":{"promptTokens":200,"completionTokens":100,"totalTokens":300,"cost":0.02}}
    """
    let stop = try! ReasonixHookEvent.from(jsonData: Data(stopJSON.utf8))
    db.upsertHookSession(event: stop)
    drainQueue(db)

    rows = collectQuery(db, sql: "SELECT total_tokens, total_cost FROM hook_sessions WHERE session_id='sess-123'")
    assertEqual(rows[0][0], "300", "total tokens updated to max")
    assertEqual(rows[0][1], "0.02", "cost updated to max")

    print("✅ upsertHookSession works")
}

// Test: startHookToolCall + finishHookToolCall
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    db.startHookToolCall(sessionId: "sess-1", turn: 1, toolName: "read_file",
                         toolArgsJSON: "{\"path\":\"a.swift\"}", timestamp: "2026-08-03T10:00:00.000Z")
    drainQueue(db)

    var rows = collectQuery(db, sql: "SELECT tool_name, status, tool_args_json FROM hook_tool_calls")
    assertEqual(rows.count, 1, "tool call should be created")
    if rows.count >= 1 {
        assertEqual(rows[0][0], "read_file", "tool name")
        assertEqual(rows[0][1], "started", "initial status")
        assertEqual(rows[0][2], "{\"path\":\"a.swift\"}", "tool args json")
    }

    db.finishHookToolCall(sessionId: "sess-1", turn: 1, toolName: "read_file",
                          status: "success", resultPreview: "ok", error: nil,
                          timestamp: "2026-08-03T10:00:05.000Z")
    drainQueue(db)

    rows = collectQuery(db, sql: "SELECT status, duration_ms FROM hook_tool_calls")
    assertEqual(rows[0][0], "success", "status updated")
    assertNotNil(rows[0][1], "duration should be computed")

    print("✅ startHookToolCall + finishHookToolCall works")
}

// Test: 空表查询
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let rows = collectQuery(db, sql: "SELECT * FROM hook_events")
    assertEqual(rows.count, 0, "empty table should return 0 rows")
    print("✅ query returns empty for empty table")
}

// Test: cost 字段 USD→CNY 迁移（v1）
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    // 模拟旧库：user_version 复位为 0，插入 USD 金额
    db.query(sql: "PRAGMA user_version = 0") { _ in }
    db.query(sql: """
        INSERT INTO hook_events (event_type, event_type_cn, session_id, cost, timestamp, created_at)
        VALUES ('Stop', '轮次完成', 'sess-mig', 1.0, '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z')
        """) { _ in }
    db.query(sql: """
        INSERT INTO hook_sessions (session_id, total_cost, status, updated_at)
        VALUES ('sess-mig', 2.0, 'ended', '2026-08-01T00:00:00Z')
        """) { _ in }

    db.migrateIfNeeded()

    let rows = collectQuery(db, sql: "SELECT cost FROM hook_events WHERE session_id='sess-mig'")
    assertEqual(rows[0][0], "7.2", "hook_events.cost migrated USD→CNY (×7.2)")
    let srows = collectQuery(db, sql: "SELECT total_cost FROM hook_sessions WHERE session_id='sess-mig'")
    assertEqual(srows[0][0], "14.4", "hook_sessions.total_cost migrated USD→CNY (×7.2)")

    // 幂等：再次执行不重复放大
    db.migrateIfNeeded()
    let rows2 = collectQuery(db, sql: "SELECT cost FROM hook_events WHERE session_id='sess-mig'")
    assertEqual(rows2[0][0], "7.2", "migration is idempotent")

    print("✅ cost USD→CNY 迁移 works")
}

// Test: 时区与货币配置
do {
    let offset = SqliteTimeZone.offsetModifier
    assertEqual(offset.hasSuffix(" hours"), true, "offset should be 'N hours' format, got: \(offset)")

    // 汇率默认 7.2，可被 UserDefaults 覆盖
    UserDefaults.standard.removeObject(forKey: CurrencyConfig.rateOverrideKey)
    assertEqual(CurrencyConfig.usdToCnyRate, 7.2, "default rate 7.2")
    assertEqual(CurrencyConfig.usdToCny(1.0), 7.2, "usdToCny conversion")

    print("✅ 时区与货币配置 works")
}

// Test: 过期数据清理（90 天保留）
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    // 插入一条 200 天前的旧事件和一条今天的事件
    let oldDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-200 * 86400))
    let todayDate = ISO8601DateFormatter().string(from: Date())
    db.query(sql: """
        INSERT INTO hook_events (event_type, event_type_cn, session_id, total_tokens, timestamp, created_at)
        VALUES ('Stop', '轮次完成', 'sess-old', 10, '\(oldDate)', '\(oldDate)'),
               ('Stop', '轮次完成', 'sess-new', 20, '\(todayDate)', '\(todayDate)')
        """) { _ in }

    db.purgeExpiredData()

    let rows = collectQuery(db, sql: "SELECT session_id FROM hook_events ORDER BY session_id")
    assertEqual(rows.count, 1, "old event should be purged")
    assertEqual(rows[0][0], "sess-new", "new event should remain")

    print("✅ 过期数据清理 works")
}

// MARK: - Test TokenUsageProvider（核心业务）

print("\n🧪 Testing TokenUsageProvider...")

// Helper: 构造今天的 ISO8601 时间戳（UTC）
func todayISO(_ addingMinutes: Int = 0) -> String {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fmt.string(from: Date().addingTimeInterval(TimeInterval(addingMinutes * 60)))
}

func makeHookEvent(type: ReasonixHookEventType, sessionId: String, tokens: Int, cost: Double,
                   model: String = "gpt-5", project: String = "toolbar") throws -> ReasonixHookEvent {
    let json = """
    {"event":"\(type.rawValue)","sessionId":"\(sessionId)","model":"\(model)","project":"\(project)","timestamp":"\(todayISO())","usage":{"promptTokens":\(tokens / 2),"completionTokens":\(tokens / 2),"totalTokens":\(tokens),"cost":\(cost)}}
    """
    return try ReasonixHookEvent.from(jsonData: Data(json.utf8))
}

func drainDB(_ db: DatabaseManager) {
    db.query(sql: "SELECT 1") { _ in }
}

// 今日统计：总计/汇总/每小时/历史/模型/项目排行
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let provider = TokenUsageProvider(database: db)

    let stop = try makeHookEvent(type: .stop, sessionId: "s1", tokens: 100, cost: 0.01)
    db.writeHookEvent(event: stop)
    db.upsertHookSession(event: stop)
    drainDB(db)

    let total = provider.fetchTodayTotal()
    assertEqual(total.tokens, 100, "today total tokens")
    assertEqual(total.cost, 0.01, "today total cost")

    let summary = provider.fetchTodaySummary()
    assertEqual(summary.totalTokens, 100, "summary total tokens")
    assertEqual(summary.byModel.count, 1, "summary by model")

    let hourly = provider.fetchHourlyBreakdown(dateString: nil)
    assertEqual(hourly.count, 24, "hourly filled 24 hours")
    assertEqual(hourly.reduce(0) { $0 + $1.totalTokens }, 100, "hourly sum equals total")

    let history = provider.fetchDailyHistory(days: 7)
    assertEqual(history.count, 7, "daily history filled 7 days")

    let models = provider.fetchModelRanking(limit: 5)
    assertEqual(models.count, 1, "model ranking count")
    assertEqual(models[0].model, "gpt-5", "model name")

    let projects = provider.fetchProjectRanking(limit: 5)
    assertEqual(projects.count, 1, "project ranking count")
    assertEqual(projects[0].project, "toolbar", "project name")

    print("✅ TokenUsageProvider 今日统计 works")
}

// 工具调用：排行 + 最近调用
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let provider = TokenUsageProvider(database: db)

    db.startHookToolCall(sessionId: "s1", turn: 1, toolName: "read_file", toolArgsJSON: nil, timestamp: todayISO())
    db.startHookToolCall(sessionId: "s1", turn: 2, toolName: "read_file", toolArgsJSON: nil, timestamp: todayISO())
    db.startHookToolCall(sessionId: "s1", turn: 3, toolName: "bash", toolArgsJSON: nil, timestamp: todayISO())
    drainDB(db)
    db.finishHookToolCall(sessionId: "s1", turn: 1, toolName: "read_file", status: "success", resultPreview: nil, error: nil, timestamp: todayISO(1))
    db.finishHookToolCall(sessionId: "s1", turn: 2, toolName: "read_file", status: "failure", resultPreview: nil, error: "boom", timestamp: todayISO(2))
    db.finishHookToolCall(sessionId: "s1", turn: 3, toolName: "bash", status: "success", resultPreview: nil, error: nil, timestamp: todayISO(3))
    drainDB(db)

    let ranking = provider.fetchToolCallRanking(limit: 5)
    assertEqual(ranking.count, 2, "tool ranking count")
    let readFile = ranking.first { $0.toolName == "read_file" }
    assertEqual(readFile?.callCount, 2, "read_file call count")
    assertEqual(readFile?.successRate, 50, "read_file success rate")
    let bash = ranking.first { $0.toolName == "bash" }
    assertEqual(bash?.successRate, 100, "bash success rate")

    let recent = provider.fetchRecentToolCalls(limit: 5)
    assertEqual(recent.count, 3, "recent tool calls")

    print("✅ TokenUsageProvider 工具统计 works")
}

// 会话概览：StopFailure 应标记 failed
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let provider = TokenUsageProvider(database: db)

    let active = try makeHookEvent(type: .sessionStart, sessionId: "s-active", tokens: 0, cost: 0)
    let failed = try makeHookEvent(type: .stopFailure, sessionId: "s-failed", tokens: 50, cost: 0.01)
    db.upsertHookSession(event: active)
    db.upsertHookSession(event: failed)
    drainDB(db)

    var statuses: [String] = []
    db.query(sql: "SELECT status FROM hook_sessions ORDER BY session_id") { stmt in
        statuses.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
    assertEqual(statuses.count, 2, "two sessions")
    assertEqual(statuses.contains("failed"), true, "StopFailure session marked failed")

    let stats = provider.fetchSessionOverviewStats()
    assertEqual(stats.activeSessions, 1, "active sessions")
    assertEqual(stats.todayTotal, 2, "today sessions")
    assertEqual(stats.todayFailed, 1, "today failed")
    assertEqual(stats.failRate, 50, "fail rate")

    print("✅ TokenUsageProvider 会话概览 works")
}

// 空库容错
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let provider = TokenUsageProvider(database: db)

    assertEqual(provider.fetchTodayTotal().tokens, 0, "empty total")
    assertEqual(provider.fetchTodaySummary().totalTokens, 0, "empty summary")
    assertEqual(provider.fetchHourlyBreakdown(dateString: nil).count, 24, "empty hourly")
    assertEqual(provider.fetchDailyHistory(days: 7).count, 7, "empty history")
    assertEqual(provider.fetchToolCallRanking(limit: 5).isEmpty, true, "empty ranking")
    assertEqual(provider.fetchModelRanking(limit: 5).isEmpty, true, "empty models")
    assertEqual(provider.fetchSessionOverviewStats().activeSessions, 0, "empty active")

    print("✅ TokenUsageProvider 空库容错 works")
}

// MARK: - Done

print("\n🎉 所有测试通过！")
