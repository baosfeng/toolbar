import Foundation
import NetworkMonitorCore

// MARK: - Copilot 回归（上游源码核实后修掉的 4 类缺陷）
//
// 防复发：datetime('now') 的 UTC 文本时间被当本地时间偏移 8 小时 /
// reasoning_tokens 被并进 output 虚高 / UNIQUE(session_id, event_id) 没镜像导致重复行双计 /
// COPILOT_HOME 不被当作 sessions home。
// fixture 全部自造（字典行 + /tmp 临时 SQLite），不读真实 ~/.copilot。

/// UTC 文本时间 → 期望 epoch 毫秒（1795327920000 = 2026-11-22T06:12:00Z）
private let copilotUTCDateTime = "2026-11-22 06:12:00"
private let copilotUTCMilliseconds: Int64 = 1_795_327_920_000

private func copilotRow(session: String, event: String?, output: Int, reasoning: Int = 0,
                        input: Int = 800, cacheRead: Int = 0,
                        created: Any = "2026-11-22 06:12:00") -> [String: Any] {
    var row: [String: Any] = [
        "session_id": session,
        "input_tokens": input,
        "output_tokens": output,
        "cache_read_tokens": cacheRead,
        "created_at": created,
    ]
    if reasoning > 0 { row["reasoning_tokens"] = reasoning }
    if let event { row["event_id"] = event }
    return row
}

func runCopilotUsageRegressionTests() {
    print("🧪 Testing Copilot 回归（UTC 文本时间 / reasoning 不并桶 / 事件去重 / COPILOT_HOME）...")

    // MARK: 9. datetime('now') 文本按 UTC 解释（本机时区 +08 也不能偏 8 小时）
    if case .usage(let utcEvent) = CopilotUsageParser.parse(
        row: copilotRow(session: "s-utc", event: "e-utc", output: 500, input: 100)) {
        assertEqual(utcEvent.tsMs, copilotUTCMilliseconds,
                    "UTC 文本：" + copilotUTCDateTime + " → 1795327920000")
    } else {
        assertEqual(false, true, "UTC 文本：应解析为 usage")
    }

    // MARK: 10. reasoning_tokens 不并入 output
    if case .usage(let noMerge) = CopilotUsageParser.parse(
        row: copilotRow(session: "s-r", event: "e-r", output: 500, reasoning: 100, input: 800)) {
        assertEqual(noMerge.usage.output, 500, "reasoning：有该列时 output 仍是 500（不是 600）")
        assertEqual(noMerge.usage.totalTokens, 1300, "reasoning：四桶里没有单独一桶给它")
    } else {
        assertEqual(false, true, "reasoning：应解析为 usage")
    }
    let reasoningTable = CopilotUsageParser.parse(
        rows: [copilotRow(session: "s-r", event: "e-1", output: 500, reasoning: 100),
               copilotRow(session: "s-r", event: "e-2", output: 250)],
        tableColumns: ["input_tokens", "output_tokens", "reasoning_tokens", "created_at",
                       "session_id", "event_id"])
    assertEqual(reasoningTable.usage.output, 750, "reasoning：整表 output 750（并入会变 850）")
    assertEqual(reasoningTable.events.count, 2, "reasoning：两行都计入")

    // MARK: 11. (session_id, event_id) 去重；event_id 为 NULL 的行按行 id 各留
    let rows: [[String: Any]] = [
        ["session_id": "s1", "event_id": "e1", "input_tokens": 800, "output_tokens": 500,
         "created_at": 1_795_327_920],
        ["session_id": "s1", "event_id": "e1", "input_tokens": 800, "output_tokens": 500,
         "created_at": 1_795_327_920],
        ["id": "row-3", "session_id": "s1", "input_tokens": 600, "output_tokens": 250,
         "created_at": 1_795_327_921],
        ["id": "row-4", "session_id": "s1", "input_tokens": 100, "output_tokens": 50,
         "created_at": 1_795_327_922],
        ["session_id": "s2", "event_id": "e1", "input_tokens": 50, "output_tokens": 10,
         "created_at": 1_795_327_923],
    ]
    let deduped = CopilotUsageParser.parse(rows: rows, tableColumns: [])
    assertEqual(deduped.events.count, 4, "去重：5 行 → 4 事件")
    assertEqual(deduped.skippedLineCount, 1, "去重：重复的 (session_id, event_id) 计 skipped=1")
    assertEqual(deduped.malformedLineCount, 0, "去重：无坏行")
    assertEqual(deduped.events.map(\.usage.uncachedInput).sorted(), [50, 100, 600, 800],
                "去重：event_id 为 NULL 的两行按行 id 各留一份")
    assertEqual(deduped.events.map(\.usage.output).sorted(), [10, 50, 250, 500],
                "去重：保留的是各行的真实用量")

    // 整库读取：同一套行进 SQLite（read 会补 rowid 别名兜底 NULL event_id）
    let dbPath = tokenSourceTempDatabasePath("copilot-regression")
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    func literal(_ value: Any?) -> String {
        if let value = value as? String { return tokenSourceTextLiteral(value) }
        if let value = value as? Int { return String(value) }
        return "NULL"
    }
    let values = rows.map { row in
        "(" + literal(row["id"]) + ", " + literal(row["session_id"]) + ", " + literal(row["event_id"])
            + ", " + literal(row["input_tokens"]) + ", " + literal(row["output_tokens"])
            + ", " + literal(row["created_at"]) + ")"
    }.joined(separator: ", ")
    guard tokenSourceMakeSQLite(at: dbPath, statements: [
        "CREATE TABLE assistant_usage_events (id TEXT, session_id TEXT, event_id TEXT, "
            + "input_tokens INTEGER, output_tokens INTEGER, created_at TEXT);",
        "INSERT INTO assistant_usage_events (id, session_id, event_id, input_tokens, output_tokens, "
            + "created_at) VALUES " + values + ";",
    ]) else {
        assertEqual(false, true, "整库：fixture 建库失败")
        return
    }
    let read = CopilotUsageParser.read(databaseAt: dbPath)
    assertEqual(read.isAvailable, true, "整库：可读")
    assertEqual(read.events.count, 4, "整库：去重后 4 事件")
    assertEqual(read.skippedRowCount, 1, "整库：重复键仍只算一次")

    // MARK: 12. COPILOT_HOME 是 sessions home（db 直接落在它下面）
    let fixtureHome = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
    let withEnv = HarnessSourceDiscovery.roots(for: .copilot, storage: InMemoryStorage(),
                                              homeDirectory: fixtureHome,
                                              environment: ["COPILOT_HOME": "/tmp/gh-copilot"])
    assertEqual(withEnv.first?.path, "/tmp/gh-copilot/session-store.db",
                "COPILOT_HOME：根为 /tmp/x/session-store.db")
    assertEqual(HarnessSQLiteSourceReader.databasePath(for: .copilot, storage: InMemoryStorage(),
                                                       homeDirectory: fixtureHome,
                                                       environment: ["COPILOT_HOME": "/tmp/gh-copilot"]),
                "/tmp/gh-copilot/session-store.db", "COPILOT_HOME：读取器取到同一个库")
    let withoutEnv = HarnessSourceDiscovery.roots(for: .copilot, storage: InMemoryStorage(),
                                                 homeDirectory: fixtureHome, environment: [:])
    assertEqual(withoutEnv.first?.path, "/Users/fixture/.copilot/session-store.db",
                "无环境变量：回落到 ~/.copilot/session-store.db")

    print("✅ Copilot 回归 works")
}
