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

// MARK: - Done

print("\n🎉 所有测试通过！")
