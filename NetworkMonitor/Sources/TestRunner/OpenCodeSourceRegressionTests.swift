import Foundation
import NetworkMonitorCore

// MARK: - OpenCode 回归（v2 表名 / part 双计 / compaction / 双代并存 / 库定位）
//
// 防复发：只认 v1 表名会整源 0 数据 / 读 part 表会把 input 双计（1200 → 3000）/
// 按 role 过滤会漏掉 compaction 自身用量 / 两代表并存时两张都读会双算 /
// OPENCODE_DB 与渠道后缀库（opencode-<channel>.db）不被识别。

private let v2SessionModel = """
{"id":"claude-sonnet-4-5","providerID":"anthropic"}
"""

private func openCodeV2Fixture(at path: String) -> Bool {
    let m1 = """
{"model":{"providerID":"anthropic","id":"claude-sonnet-4-5"},"tokens":{"input":1000,"output":400,"reasoning":100,"cache":{"read":300,"write":50}}}
"""
    let m2 = """
{"providerID":"anthropic","modelID":"claude-haiku-4-5","tokens":{"input":500,"output":100,"cache":{"read":400,"write":80}}}
"""
    let m3 = """
{"tokens":{"input":300,"output":20,"cache":{"read":250}}}
"""
    return tokenSourceMakeSQLite(at: path, statements: [
        "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT, model TEXT);",
        "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, "
            + "time_created INTEGER, data TEXT);",
        "CREATE TABLE session_part (id TEXT PRIMARY KEY, session_id TEXT, message_id TEXT, "
            + "tokens TEXT);",
        "INSERT INTO session_v2 VALUES ('ses-1', '/tmp/oc-v2', NULL, "
            + tokenSourceTextLiteral(v2SessionModel) + ");",
        "INSERT INTO session_message VALUES ('m1', 'ses-1', 1767585600000, " + tokenSourceTextLiteral(m1) + ");",
        "INSERT INTO session_message VALUES ('m2', 'ses-1', 1767585610000, " + tokenSourceTextLiteral(m2) + ");",
        "INSERT INTO session_message VALUES ('m3', 'ses-1', 1767585620000, " + tokenSourceTextLiteral(m3) + ");",
        "INSERT INTO session_part VALUES ('p1', 'ses-1', 'm1', '{\"input\":3000,\"output\":900}');",
    ])
}

func runOpenCodeSourceRegressionTests() {
    print("🧪 Testing OpenCode 回归（v2 嗅探 / part 不双计 / compaction / 双代 / 定位）...")

    // MARK: 16 + 17. v2 表名嗅探 + part 不参与统计
    let v2Path = tokenSourceTempDatabasePath("oc-v2")
    defer { try? FileManager.default.removeItem(atPath: v2Path) }
    guard openCodeV2Fixture(at: v2Path) else {
        assertEqual(false, true, "v2：fixture 建库失败")
        return
    }
    let probe = OpenCodeSchema.probe(databaseAt: v2Path)
    assertEqual(probe.version, OpenCodeSchemaVersion.v2, "v2：嗅探选中 v2 布局")
    assertEqual(probe.tables.contains("session_message"), true, "v2：诊断列出 v2 表名")
    let v2Read = OpenCodeMessageParser.read(databaseAt: v2Path)
    assertEqual(v2Read.isAvailable, true, "v2：可读")
    assertEqual(v2Read.events.count, 3, "v2：三条消息各一个事件")
    assertEqual(v2Read.usage, HarnessTokenUsage(uncachedInput: 1800, output: 620,
                                                cacheRead: 950, cacheWrite: 130, requestCount: 3),
                "v2：四桶 1800 / 620 / 950 / 130，requests=3")
    assertEqual(v2Read.requestCount, 3, "v2：requests=3")
    assertEqual(v2Read.events.first?.model, "claude-sonnet-4-5", "v2：model{providerID,id} 形状")
    assertEqual(v2Read.events.first?.cwd, "/tmp/oc-v2", "v2：cwd 取 session_v2.directory")

    // part 表里的 tokens 不得累加（否则 input 从 1200 变 3000）
    let partPath = tokenSourceTempDatabasePath("oc-part")
    defer { try? FileManager.default.removeItem(atPath: partPath) }
    let single = """
{"tokens":{"input":1200,"output":100}}
"""
    guard tokenSourceMakeSQLite(at: partPath, statements: [
        "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT);",
        "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, "
            + "time_created INTEGER, data TEXT);",
        "CREATE TABLE session_part (id TEXT PRIMARY KEY, session_id TEXT, tokens TEXT);",
        "INSERT INTO session_v2 VALUES ('ses-p', '/tmp/oc-part', NULL);",
        "INSERT INTO session_message VALUES ('m1', 'ses-p', 1767585600000, "
            + tokenSourceTextLiteral(single) + ");",
        "INSERT INTO session_part VALUES ('p1', 'ses-p', '{\"input\":3000}');",
    ]) else {
        assertEqual(false, true, "part：fixture 建库失败")
        return
    }
    let partRead = OpenCodeMessageParser.read(databaseAt: partPath)
    assertEqual(partRead.usage.uncachedInput, 1200, "part：input 保持 1200（读 part 会变 3000）")
    assertEqual(partRead.events.count, 1, "part：只算消息层一条")

    // MARK: 18 + 20（模型兜底）. compaction 消息（无 model）计入并回落到会话模型
    let compactionPath = tokenSourceTempDatabasePath("oc-compaction")
    defer { try? FileManager.default.removeItem(atPath: compactionPath) }
    let compaction = """
{"role":"compaction","tokens":{"input":200,"output":50}}
"""
    guard tokenSourceMakeSQLite(at: compactionPath, statements: [
        "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT, model TEXT);",
        "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, "
            + "time_created INTEGER, data TEXT);",
        "INSERT INTO session_v2 VALUES ('ses-c', '/tmp/oc-compaction', NULL, "
            + tokenSourceTextLiteral(v2SessionModel) + ");",
        "INSERT INTO session_message VALUES ('m-compaction', 'ses-c', 1767585600000, "
            + tokenSourceTextLiteral(compaction) + ");",
    ]) else {
        assertEqual(false, true, "compaction：fixture 建库失败")
        return
    }
    let compactionRead = OpenCodeMessageParser.read(databaseAt: compactionPath)
    assertEqual(compactionRead.events.count, 1, "compaction：role 不是 assistant 也计入")
    assertEqual(compactionRead.usage.uncachedInput, 200, "compaction：用量计入")
    assertEqual(compactionRead.events.first?.model, "claude-sonnet-4-5",
                "compaction：模型用会话行兜底（不是 opencode/unknown）")
    assertEqual(compactionRead.events.first?.provider, "anthropic", "compaction：provider 也来自会话兜底")

    // MARK: 19. v1 / v2 表并存：只读新表，v1 的假数据不计
    let bothPath = tokenSourceTempDatabasePath("oc-both")
    defer { try? FileManager.default.removeItem(atPath: bothPath) }
    let v1Message = """
{"tokens":{"input":9999,"output":9999}}
"""
    let v2Message = """
{"tokens":{"input":100,"output":10}}
"""
    guard tokenSourceMakeSQLite(at: bothPath, statements: [
        "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT);",
        "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);",
        "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT, parent_id TEXT);",
        "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, "
            + "time_created INTEGER, data TEXT);",
        "INSERT INTO session VALUES ('ses-v1', '/tmp/oc-v1', NULL);",
        "INSERT INTO message VALUES ('old-1', 'ses-v1', 1767585600000, "
            + tokenSourceTextLiteral(v1Message) + ");",
        "INSERT INTO session_v2 VALUES ('ses-v2', '/tmp/oc-v2', NULL);",
        "INSERT INTO session_message VALUES ('new-1', 'ses-v2', 1767585600000, "
            + tokenSourceTextLiteral(v2Message) + ");",
    ]) else {
        assertEqual(false, true, "双代：fixture 建库失败")
        return
    }
    let bothProbe = OpenCodeSchema.probe(databaseAt: bothPath)
    assertEqual(bothProbe.version, OpenCodeSchemaVersion.v2, "双代：优先新表")
    let bothRead = OpenCodeMessageParser.read(databaseAt: bothPath)
    assertEqual(bothRead.events.count, 1, "双代：只读一张表")
    assertEqual(bothRead.usage, HarnessTokenUsage(uncachedInput: 100, output: 10,
                                                  cacheRead: 0, cacheWrite: 0, requestCount: 1),
                "双代：v1 的 9999 不计（会双算到 10099）")

    // MARK: 20. OPENCODE_DB / 渠道后缀库 / 默认目录
    let envLocation = OpenCodeDatabaseLocation.resolve(environment: ["OPENCODE_DB": "/tmp/x/oc.db"])
    assertEqual(envLocation.url.path, "/tmp/x/oc.db", "定位：OPENCODE_DB 原样采用")
    assertEqual(envLocation.origin, OpenCodeDatabaseLocation.Origin.environmentVariable,
                "定位：来源标记为环境变量")
    assertEqual(HarnessSQLiteSourceReader.databasePath(
        for: .opencode, storage: InMemoryStorage(),
        homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
        environment: ["OPENCODE_DB": "/tmp/x/oc.db"]),
                "/tmp/x/oc.db", "定位：读取器同样取 OPENCODE_DB")

    let channelBase = tokenRegressionTempDirectory("opencode-channel")
    defer { try? FileManager.default.removeItem(atPath: channelBase) }
    let channelDirectory = channelBase + "/opencode"
    tokenRegressionWrite("db-dev", to: channelDirectory + "/opencode-dev.db")
    tokenRegressionWrite("db-beta", to: channelDirectory + "/opencode-beta.db")
    let oldDate = Date(timeIntervalSince1970: 1_767_225_600)
    let newDate = Date(timeIntervalSince1970: 1_767_312_000)
    try? FileManager.default.setAttributes([.modificationDate: oldDate],
                                           ofItemAtPath: channelDirectory + "/opencode-dev.db")
    try? FileManager.default.setAttributes([.modificationDate: newDate],
                                           ofItemAtPath: channelDirectory + "/opencode-beta.db")
    let channel = OpenCodeDatabaseLocation.resolve(
        homeDirectory: URL(fileURLWithPath: channelBase),
        environment: ["XDG_DATA_HOME": channelBase])
    assertEqual(channel.url.lastPathComponent, "opencode-beta.db", "定位：主库缺失时取最新渠道库")
    assertEqual(channel.origin, OpenCodeDatabaseLocation.Origin.channelVariant(name: "opencode-beta.db"),
                "定位：来源标记为渠道库")
    assertEqual(channel.diagnostic.contains("渠道库"), true, "定位：诊断写明用的是渠道库")

    let defaultLocation = OpenCodeDatabaseLocation.resolve(
        homeDirectory: URL(fileURLWithPath: "/Users/fixture"), environment: [:])
    assertEqual(defaultLocation.url.path, "/Users/fixture/.local/share/opencode/opencode.db",
                "定位：默认目录 ~/.local/share/opencode/opencode.db")

    print("✅ OpenCode 回归 works")
}
