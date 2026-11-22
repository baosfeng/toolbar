import Foundation
import NetworkMonitorCore

// MARK: - OpenCode 用量解析（设计规格 §2.5 / §7）
//
// 覆盖：`output + reasoning` 的合桶口径、cache.read / cache.write 拆分、
// parent_id 子会话照常计入、无 tokens / 坏 JSON / 无时间 三种行的分类、
// message.id 去重、整库只读读取、库不存在 / 非 SQLite / 缺表 三种降级。

private let openCodeRootData = """
{"providerID":"anthropic","modelID":"claude-sonnet-4-5","tokens":{"input":1000,"output":400,"reasoning":100,"cache":{"read":300,"write":50}}}
"""
private let openCodeChildData = """
{"providerID":"anthropic","modelID":"claude-opus-4-6","tokens":{"input":500,"output":300,"cache":{"read":100,"write":0}}}
"""

/// 两行有用量 + 一行无 tokens + 两行坏行（坏 JSON / 无时间）
private func openCodeRows() -> [OpenCodeMessageParser.MessageRow] {
    [
        OpenCodeMessageParser.MessageRow(id: "msg_1", sessionID: "ses_root",
                                         timeCreatedMs: 1_767_585_600_000,
                                         data: Data(openCodeRootData.utf8)),
        OpenCodeMessageParser.MessageRow(id: "msg_user", sessionID: "ses_root",
                                         timeCreatedMs: 1_767_585_610_000,
                                         data: Data("{\"role\":\"user\",\"parts\":[]}".utf8)),
        OpenCodeMessageParser.MessageRow(id: "msg_bad_json", sessionID: "ses_root",
                                         timeCreatedMs: 1_767_585_620_000,
                                         data: Data("{broken".utf8)),
        OpenCodeMessageParser.MessageRow(id: "msg_bad_time", sessionID: "ses_root",
                                         timeCreatedMs: 0,
                                         data: Data("{\"tokens\":{\"input\":10,\"output\":1}}".utf8)),
        OpenCodeMessageParser.MessageRow(id: "msg_2", sessionID: "ses_child",
                                         timeCreatedMs: 1_767_585_630_000,
                                         data: Data(openCodeChildData.utf8)),
    ]
}

private let openCodeSessions = [
    OpenCodeMessageParser.SessionRow(id: "ses_root", directory: "/tmp/oc-root"),
    OpenCodeMessageParser.SessionRow(id: "ses_child", directory: "/tmp/oc-child", parentID: "ses_root"),
]

func runOpenCodeMessageParserTests() {
    print("🧪 Testing OpenCode 解析（output+reasoning / 子会话 / 坏行 / 整库 / 降级）...")

    // MARK: 纯入口：单行
    if case .usage(let rootEvent) = OpenCodeMessageParser.parse(
        data: Data(openCodeRootData.utf8), timeCreatedMs: 1_767_585_600_000,
        sessionID: "ses_root", cwd: "/tmp/oc-root") {
        assertEqual(rootEvent.usage, HarnessTokenUsage(uncachedInput: 1000, output: 500,
                                                       cacheRead: 300, cacheWrite: 50,
                                                       requestCount: 1),
                    "单行：msg_1 四桶 [1000,500,300,50]（output 400 + reasoning 100）")
        assertEqual(rootEvent.source, TokenSourceID.opencode, "单行：来源标识")
        assertEqual(rootEvent.provider, "anthropic", "单行：providerID")
        assertEqual(rootEvent.model, "claude-sonnet-4-5", "单行：modelID")
        assertEqual(rootEvent.sessionKey, "ses_root", "单行：会话键")
        assertEqual(rootEvent.cwd, "/tmp/oc-root", "单行：cwd")
        assertEqual(rootEvent.tsMs, 1_767_585_600_000, "单行：时间取 time_created（毫秒原样）")
    } else {
        assertEqual(false, true, "单行：msg_1 应解析为 usage")
    }
    if case .ignored = OpenCodeMessageParser.parse(
        data: Data("{\"role\":\"user\"}".utf8), timeCreatedMs: 1,
        sessionID: "s", cwd: "") {
        assertEqual(true, true, "单行：无 tokens 的用户消息归 ignored")
    } else {
        assertEqual("ignored", "非 ignored", "单行：无 tokens 的行应归 ignored")
    }
    if case .malformed = OpenCodeMessageParser.parse(
        data: Data("{broken".utf8), timeCreatedMs: 1, sessionID: "s", cwd: "") {
        assertEqual(true, true, "单行：坏 JSON 归 malformed")
    } else {
        assertEqual("malformed", "非 malformed", "单行：坏 JSON 应归 malformed")
    }
    if case .malformed = OpenCodeMessageParser.parse(
        data: Data(openCodeRootData.utf8), timeCreatedMs: 0, sessionID: "s", cwd: "") {
        assertEqual(true, true, "单行：缺时间归 malformed（不记到 1970）")
    } else {
        assertEqual("malformed", "非 malformed", "单行：缺时间应归 malformed")
    }

    // MARK: 整表入口
    let report = OpenCodeMessageParser.parse(rows: openCodeRows(), sessions: openCodeSessions)
    assertEqual(report.source, TokenSourceID.opencode, "整表：来源标识")
    assertEqual(report.events.count, 2, "整表：两条用量行")
    assertEqual(report.usage, HarnessTokenUsage(uncachedInput: 1500, output: 800,
                                                cacheRead: 400, cacheWrite: 50, requestCount: 2),
                "整表：四桶合计 1500 / 800 / 400 / 50")
    assertEqual(report.requestCount, 2, "整表：requests=2")
    assertEqual(report.ignoredLineCount, 1, "整表：无 tokens 行记 ignored")
    assertEqual(report.malformedLineCount, 2, "整表：坏 JSON + 缺时间各一条")
    assertEqual(report.skippedLineCount, 0, "整表：无重复 id")
    assertEqual(report.events.last?.cwd, "/tmp/oc-child", "整表：parent_id 子会话照常计入（cwd 取子会话目录）")
    assertEqual(report.events.last?.model, "claude-opus-4-6", "整表：子会话模型")
    assertEqual(report.session, nil, "整表：SQLite 来源不产出会话元信息")

    // 重复 id 兜底去重
    let duplicateRows = [
        OpenCodeMessageParser.MessageRow(id: "dup", sessionID: "s", timeCreatedMs: 1,
                                         data: Data(openCodeRootData.utf8)),
        OpenCodeMessageParser.MessageRow(id: "dup", sessionID: "s", timeCreatedMs: 2,
                                         data: Data(openCodeRootData.utf8)),
    ]
    let deduped = OpenCodeMessageParser.parse(rows: duplicateRows)
    assertEqual(deduped.events.count, 1, "去重：同一 message.id 只算一次")
    assertEqual(deduped.skippedLineCount, 1, "去重：第二条计 skipped")

    // MARK: 整库读取
    let dbPath = tokenSourceTempDatabasePath("opencode")
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    func messageInsert(_ row: OpenCodeMessageParser.MessageRow) -> String {
        "(" + tokenSourceTextLiteral(row.id) + ", " + tokenSourceTextLiteral(row.sessionID) + ", "
            + String(row.timeCreatedMs) + ", "
            + tokenSourceTextLiteral(String(decoding: row.data, as: UTF8.self)) + ")"
    }
    let sessionInsert = openCodeSessions.map {
        "(" + tokenSourceTextLiteral($0.id) + ", " + tokenSourceTextLiteral($0.directory) + ", "
            + tokenSourceTextLiteral($0.parentID ?? "") + ")"
    }.joined(separator: ", ")
    guard tokenSourceMakeSQLite(at: dbPath, statements: [
        "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT);",
        "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);",
        "INSERT INTO session (id, directory, parent_id) VALUES " + sessionInsert + ";",
        "INSERT INTO message (id, session_id, time_created, data) VALUES "
            + openCodeRows().map(messageInsert).joined(separator: ", ") + ";",
    ]) else {
        assertEqual(false, true, "整库：fixture 建库失败")
        return
    }
    let read = OpenCodeMessageParser.read(databaseAt: dbPath)
    assertEqual(read.isAvailable, true, "整库：可读")
    assertEqual(read.events.count, 2, "整库：两条事件")
    assertEqual(read.usage, report.usage, "整库：与整表入口同口径")
    assertEqual(read.requestCount, 2, "整库：requests=2")
    assertEqual(read.ignoredRowCount, 1, "整库：ignored 计数透传")
    assertEqual(read.malformedRowCount, 2, "整库：malformed 计数透传")

    // MARK: 降级：库不存在 / 非 SQLite / 缺表
    let missing = OpenCodeMessageParser.read(databaseAt: tokenSourceTempDatabasePath("opencode-missing"))
    assertEqual(missing.isAvailable, false, "降级：库不存在 → available=false")
    assertEqual(missing.events.count, 0, "降级：库不存在 → 零事件")
    assertEqual(missing.usage, HarnessTokenUsage.zero, "降级：库不存在 → 四桶全 0")
    assertEqual(missing.unavailable?.displayMessage.isEmpty == false, true, "降级：库不存在带原因文案")

    let garbagePath = tokenSourceTempDatabasePath("opencode-garbage")
    defer { try? FileManager.default.removeItem(atPath: garbagePath) }
    _ = FileManager.default.createFile(atPath: garbagePath, contents: Data("not a sqlite database".utf8))
    let garbage = OpenCodeMessageParser.read(databaseAt: garbagePath)
    assertEqual(garbage.isAvailable, false, "降级：非 SQLite 文件 → available=false")
    assertEqual(garbage.events.count, 0, "降级：非 SQLite 文件 → 零事件")
    assertEqual(garbage.unavailable?.displayMessage.isEmpty == false, true, "降级：非 SQLite 文件带原因文案")

    let tableMissingPath = tokenSourceTempDatabasePath("opencode-notable")
    defer { try? FileManager.default.removeItem(atPath: tableMissingPath) }
    _ = tokenSourceMakeSQLite(at: tableMissingPath, statements: ["CREATE TABLE other (id TEXT);"])
    let noTable = OpenCodeMessageParser.read(databaseAt: tableMissingPath)
    assertEqual(noTable.isAvailable, false, "降级：缺 message 表 → available=false")
    assertEqual(noTable.events.count, 0, "降级：缺表 → 零事件")
    if case .tableMissing(let table)? = noTable.unavailable {
        assertEqual(table, "message", "降级：缺表原因指出 message 表")
    } else {
        assertEqual("tableMissing", String(describing: noTable.unavailable), "降级：缺表原因分类")
    }

    print("✅ OpenCode 解析 works")
}
