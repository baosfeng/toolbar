import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - Zed thread 解析（设计规格 §2.6 / §7）
//
// 覆盖：request_token_usage 逐请求 + cumulative-remainder 补齐（补齐后与
// cumulative_token_usage 完全对齐、remainder requestCount=0）/ 旧 json 行 /
// zstd 解压往返 / 坏 zstd 与坏 JSON 只返回 nil 不中断 / 整库 read+scan / 降级。
//
// 本文件同时提供 P2 的 SQLite 夹具辅助（OpenCode / Copilot 套件复用）：
// 全部在 /tmp 下新建独立文件，不依赖任何人留下的残留。

// MARK: - 共享夹具辅助（SQLite / zstd）

/// 建临时 SQLite 库并执行若干 SQL（一条 SQL 一次 exec）
func tokenSourceMakeSQLite(at path: String, statements: [String]) -> Bool {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
          let db else { return false }
    defer { sqlite3_close(db) }
    for sql in statements where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { return false }
    return true
}

/// BLOB 字面量（测试不建参数绑定，避免与生产绑定口径混在一起）
func tokenSourceBlobLiteral(_ data: Data) -> String {
    "X'" + data.map { String(format: "%02x", $0) }.joined() + "'"
}

/// TEXT 字面量（单引号转义）
func tokenSourceTextLiteral(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
}

/// 每个用例独立一个临时库文件
func tokenSourceTempDatabasePath(_ name: String) -> String {
    NSTemporaryDirectory() + "token-source-" + name + "-" + UUID().uuidString + ".db"
}

/// 把 JSON 压成 zstd blob（系统 zstd 不可用时返回 nil，相关用例逐条跳过）
func tokenSourceZstdBlob(json: String, zstdPath: String) -> Data? {
    let directory = NSTemporaryDirectory() + "token-source-zstd-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let plain = directory + "/thread.json"
    let archive = directory + "/thread.json.zst"
    guard (try? Data(json.utf8).write(to: URL(fileURLWithPath: plain))) != nil else { return nil }
    guard harnessCompress(zstdPath: zstdPath, from: plain, to: archive) else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: archive))
}

// MARK: - fixture

/// map 两条（3500/500/700/200）+ cumulative 5000/600/1000/300 → 差额 1500/100/300/100
private let zedThreadJSON = """
{"model":{"provider":"zed.dev","model":"claude-sonnet-4-5"},"project_path":"/tmp/zed-proj","request_token_usage":{"msg-1":{"input_tokens":2000,"output_tokens":300,"cache_read_input_tokens":400,"cache_creation_input_tokens":100},"msg-2":{"input_tokens":1500,"output_tokens":200,"cache_read_input_tokens":300,"cache_creation_input_tokens":100}},"cumulative_token_usage":{"input_tokens":5000,"output_tokens":600,"cache_read_input_tokens":1000,"cache_creation_input_tokens":300}}
"""

/// 旧 json 行（未压缩）：map 与 cumulative 相等 → 不补差额
private let zedOldJSON = """
{"model":{"provider":"zed.dev","model":"gpt-5-codex"},"project_path":"/tmp/zed-old","request_token_usage":{"m1":{"input_tokens":10,"output_tokens":2}},"cumulative_token_usage":{"input_tokens":10,"output_tokens":2}}
"""

/// map 覆盖比累计多：差额夹到 0，绝不记负数
private let zedOverCoveredJSON = """
{"model":{"provider":"zed.dev","model":"x"},"request_token_usage":{"a":{"input_tokens":100,"output_tokens":10}},"cumulative_token_usage":{"input_tokens":50,"output_tokens":5}}
"""

private let zedRemainderKey = "th-1#cumulative-remainder"
private let zedUpdatedAtMs: Int64 = 1_767_585_600_000

// MARK: - 套件

func runZedThreadParserTests() {
    print("🧪 Testing Zed thread 解析（差额补齐 / 旧 json / zstd / 整库 / 降级）...")

    // MARK: 纯入口：两条 map + 一条差额 = 与 cumulative 对齐
    guard let report = ZedThreadParser.parse(threadJSON: Data(zedThreadJSON.utf8),
                                             threadID: "th-1", updatedAtMs: zedUpdatedAtMs) else {
        assertEqual(false, true, "Zed：明文 thread JSON 解析失败")
        return
    }
    assertEqual(report.events.count, 3, "Zed：2 条 map + 1 条 cumulative-remainder")
    assertEqual(report.appliedRemainder, true, "Zed：补了差额记录")
    assertEqual(report.usage, HarnessTokenUsage(uncachedInput: 5000, output: 600,
                                                cacheRead: 1000, cacheWrite: 300, requestCount: 2),
                "Zed：四桶与 cumulative 完全对齐（requests 只算真实请求）")
    assertEqual(report.requestCount, 2, "Zed：差额记录不计请求数")
    assertEqual(report.provider, "zed.dev", "Zed：provider 取 model.provider")
    assertEqual(report.model, "claude-sonnet-4-5", "Zed：模型")
    assertEqual(report.cwd, "/tmp/zed-proj", "Zed：项目路径")
    assertEqual(report.events.first?.usage,
                HarnessTokenUsage(uncachedInput: 2000, output: 300, cacheRead: 400,
                                  cacheWrite: 100, requestCount: 1), "Zed：第一条 map 四桶")
    assertEqual(report.events.last?.sessionKey, zedRemainderKey, "Zed：差额记录用后缀会话键")
    assertEqual(report.events.last?.usage.requestCount, 0, "Zed：差额记录 requestCount = 0")
    assertEqual(report.events.allSatisfy { $0.tsMs == zedUpdatedAtMs }, true,
                "Zed：无逐请求时间，全部记在 updated_at 上")
    assertEqual(report.events.allSatisfy { $0.source == TokenSourceID.zed }, true, "Zed：来源标识")
    assertEqual(report.events.allSatisfy { $0.usage.uncachedInput >= 0 }, true, "Zed：不出现负桶")

    // map 覆盖比累计多 → 不补差额、不记负数
    if let over = ZedThreadParser.parse(threadJSON: Data(zedOverCoveredJSON.utf8),
                                        threadID: "th-over", updatedAtMs: 1) {
        assertEqual(over.appliedRemainder, false, "Zed：覆盖超出累计时不补差额")
        assertEqual(over.events.count, 1, "Zed：只保留真实 map 记录")
        assertEqual(over.usage.uncachedInput, 100, "Zed：覆盖超出时以真实记录为准")
    } else {
        assertEqual(false, true, "Zed：覆盖超出场景解析失败")
    }

    // MARK: 旧 json 行（data_type = json）
    let oldRecord = ZedThreadRecord(id: "th-json", updatedAtMs: 1_767_585_700_000,
                                    dataType: "json", data: Data(zedOldJSON.utf8))
    guard let oldReport = ZedThreadParser.parse(record: oldRecord) else {
        assertEqual(false, true, "Zed：旧 json 行解析失败")
        return
    }
    assertEqual(oldReport.events.count, 1, "Zed 旧行：一条事件")
    assertEqual(oldReport.usage, HarnessTokenUsage(uncachedInput: 10, output: 2,
                                                   cacheRead: 0, cacheWrite: 0, requestCount: 1),
                "Zed 旧行：四桶")
    assertEqual(oldReport.appliedRemainder, false, "Zed 旧行：map 与累计相等，不补差额")

    // MARK: zstd 解压往返（系统 zstd 不可用则跳过这一条）
    var zstdBlob: Data?
    if let zstdPath = harnessZstdPath() {
        zstdBlob = tokenSourceZstdBlob(json: zedThreadJSON, zstdPath: zstdPath)
    }
    if let zstdBlob {
        let record = ZedThreadRecord(id: "th-1", updatedAtMs: zedUpdatedAtMs,
                                     dataType: "zstd", data: zstdBlob)
        if let zstdReport = ZedThreadParser.parse(record: record) {
            assertEqual(zstdReport.usage, report.usage, "Zed zstd：解压后与明文同口径")
            assertEqual(zstdReport.events.count, 3, "Zed zstd：同样 3 条事件")
            assertEqual(zstdReport.appliedRemainder, true, "Zed zstd：同样补差额")
        } else {
            assertEqual(false, true, "Zed zstd：解压失败（libzstd 或 zstd 可执行文件不可用？）")
        }
    } else {
        print("⏭ zstd 可执行文件不可用，跳过 zstd 解压往返")
    }

    // 坏 zstd / 坏 JSON 只返回 nil，不中断
    assertEqual(ZedThreadParser.parse(record: ZedThreadRecord(id: "bad-zstd", updatedAtMs: 1,
                                                              dataType: "zstd",
                                                              data: Data("not-zstd".utf8))) == nil,
                true, "Zed：坏 zstd → nil")
    assertEqual(ZedThreadParser.parse(record: ZedThreadRecord(id: "bad-json", updatedAtMs: 1,
                                                              dataType: "json",
                                                              data: Data("{broken".utf8))) == nil,
                true, "Zed：坏 JSON → nil")
    assertEqual(ZedThreadParser.parse(threadJSON: Data("[]".utf8), threadID: "x", updatedAtMs: 1) == nil,
                true, "Zed：顶层不是对象 → nil")

    // MARK: 整库 read + scan（好 zstd / 旧 json / 坏 zstd 三行）
    let dbPath = tokenSourceTempDatabasePath("zed")
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let firstRowData = zstdBlob.map(tokenSourceBlobLiteral)
        ?? tokenSourceTextLiteral(zedThreadJSON)
    let firstRowType = zstdBlob == nil ? "'json'" : "'zstd'"
    let insert = "INSERT INTO threads (id, updated_at, data_type, data) VALUES "
        + "('th-1', 1767585600000, " + firstRowType + ", " + firstRowData + "), "
        + "('th-json', 1767585700000, 'json', " + tokenSourceTextLiteral(zedOldJSON) + "), "
        + "('th-bad', 1767585800000, 'zstd', " + tokenSourceBlobLiteral(Data("not-zstd".utf8)) + ");"
    guard tokenSourceMakeSQLite(at: dbPath, statements: [
        "CREATE TABLE threads (id TEXT PRIMARY KEY, updated_at INTEGER, data_type TEXT, data BLOB);",
        insert,
    ]) else {
        assertEqual(false, true, "Zed：整库 fixture 建库失败")
        return
    }
    let read = ZedThreadParser.read(databaseAt: dbPath)
    assertEqual(read.isAvailable, true, "Zed 整库：可读")
    assertEqual(read.events.count, 4, "Zed 整库：4 条事件（3 + 1）")
    assertEqual(read.usage, HarnessTokenUsage(uncachedInput: 5010, output: 602,
                                              cacheRead: 1000, cacheWrite: 300, requestCount: 3),
                "Zed 整库：四桶与请求数合计")
    assertEqual(read.requestCount, 3, "Zed 整库：requests=3")
    assertEqual(read.malformedRowCount, 1, "Zed 整库：坏 zstd 的 thread 计入 malformed")
    assertEqual(read.skippedRowCount, 0, "Zed 整库：无字段级跳过")
    assertEqual(read.parseReport.events.count, 4, "Zed 整库：与 JSONL 同形的报告")
    if let scan = ZedThreadParser.scan(databaseAt: dbPath) {
        assertEqual(scan.threadRowCount, 3, "Zed scan：线程行数含失败行")
        assertEqual(scan.failedThreadCount, 1, "Zed scan：坏 zstd 一行失败")
        assertEqual(scan.threads.count, 2, "Zed scan：成功解析 2 条 thread")
        assertEqual(scan.usage, read.usage, "Zed scan：与 read 同口径")
    } else {
        assertEqual(false, true, "Zed scan：整库应可读")
    }

    // MARK: 降级：库不存在 / 非 SQLite 文件
    let missingPath = tokenSourceTempDatabasePath("zed-missing")
    let missing = ZedThreadParser.read(databaseAt: missingPath)
    assertEqual(missing.isAvailable, false, "降级：库不存在 → available=false")
    assertEqual(missing.events.count, 0, "降级：库不存在 → 零事件")
    assertEqual(missing.usage, HarnessTokenUsage.zero, "降级：库不存在 → 四桶全 0")
    if case .fileMissing? = missing.unavailable {
        assertEqual(true, true, "降级：缺失原因分类为 fileMissing")
    } else {
        assertEqual("fileMissing", String(describing: missing.unavailable), "降级：缺失原因分类")
    }
    assertEqual(missing.unavailable?.displayMessage.isEmpty == false, true, "降级：带原因文案")
    assertEqual(ZedThreadParser.scan(databaseAt: missingPath) == nil, true, "降级：scan 返回 nil")

    let garbagePath = tokenSourceTempDatabasePath("zed-garbage")
    defer { try? FileManager.default.removeItem(atPath: garbagePath) }
    _ = FileManager.default.createFile(atPath: garbagePath, contents: Data("not a sqlite database".utf8))
    let garbage = ZedThreadParser.read(databaseAt: garbagePath)
    assertEqual(garbage.isAvailable, false, "降级：非 SQLite 文件 → available=false")
    assertEqual(garbage.events.count, 0, "降级：非 SQLite 文件 → 零事件")
    assertEqual(garbage.usage, HarnessTokenUsage.zero, "降级：非 SQLite 文件 → 四桶全 0")
    assertEqual(garbage.unavailable?.displayMessage.isEmpty == false, true, "降级：非 SQLite 文件带原因文案")

    print("✅ Zed thread 解析 works")
}
