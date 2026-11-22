import Foundation
import NetworkMonitorCore

// MARK: - Zed 旧库回归（version < 0.3.0 的 request_token_usage）
//
// 防复发：旧库的 request_token_usage 是 **Vec 按消息下标**（不是 map），只按对象解析会
// 整段丢用量（实测 requests 从 2 变 0）；无 version 键的老库走同一条旧路径；
// version = 0.3.0 的新库仍走 map 路径，行为不变。

/// 旧格式（version 0.2.0）：数组，两条逐请求用量，累计与之相等
private let zedLegacyVectorJSON = """
{"version":"0.2.0","model":{"provider":"zed.dev","model":"claude-sonnet-4-5"},"project_path":"/tmp/zed-legacy","request_token_usage":[{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":5},{"input_tokens":50,"output_tokens":5}],"cumulative_token_usage":{"input_tokens":150,"output_tokens":15,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}
"""

/// 完全没有 version 键的旧库（上游对缺失版本同样走 legacy 升级路径）
private let zedNoVersionJSON = """
{"model":{"provider":"zed.dev","model":"x"},"request_token_usage":[{"input_tokens":10,"output_tokens":1}],"cumulative_token_usage":{"input_tokens":10,"output_tokens":1}}
"""

/// 新格式（version 0.3.0）：map 形态，走原有路径
private let zedMapVersionJSON = """
{"version":"0.3.0","model":{"provider":"zed.dev","model":"y"},"request_token_usage":{"msg-1":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}},"cumulative_token_usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}
"""

func runZedLegacyThreadTests() {
    print("🧪 Testing Zed 旧库回归（Vec 逐请求 / 无 version / 0.3.0 map 不变）...")

    // MARK: 6. version < 0.3.0：数组按消息下标逐请求解析
    guard let legacy = ZedThreadParser.parse(threadJSON: Data(zedLegacyVectorJSON.utf8),
                                             threadID: "th-legacy", updatedAtMs: 1_767_585_600_000) else {
        assertEqual(false, true, "旧库：数组形态应能解析")
        return
    }
    assertEqual(legacy.events.count, 2, "旧库：两条逐请求事件（改前 0 条）")
    assertEqual(legacy.requestCount, 2, "旧库：requests=2（改前 0）")
    assertEqual(legacy.usage, HarnessTokenUsage(uncachedInput: 150, output: 15,
                                                cacheRead: 20, cacheWrite: 5, requestCount: 2),
                "旧库：四桶 150 / 15 / 20 / 5")
    assertEqual(legacy.appliedRemainder, false, "旧库：数组之和等于累计，不补差额")
    assertEqual(legacy.events.first?.usage,
                HarnessTokenUsage(uncachedInput: 100, output: 10, cacheRead: 20,
                                  cacheWrite: 5, requestCount: 1), "旧库：首条逐请求四桶")
    assertEqual(legacy.events.last?.usage,
                HarnessTokenUsage(uncachedInput: 50, output: 5, cacheRead: 0,
                                  cacheWrite: 0, requestCount: 1), "旧库：次条逐请求四桶")

    // MARK: 7. 无 version 键也要能读
    guard let noVersion = ZedThreadParser.parse(threadJSON: Data(zedNoVersionJSON.utf8),
                                                threadID: "th-noversion", updatedAtMs: 1) else {
        assertEqual(false, true, "无 version：应能解析")
        return
    }
    assertEqual(noVersion.events.count, 1, "无 version：一条事件")
    assertEqual(noVersion.usage, HarnessTokenUsage(uncachedInput: 10, output: 1,
                                                   cacheRead: 0, cacheWrite: 0, requestCount: 1),
                "无 version：四桶 10 / 1 / 0 / 0")
    assertEqual(noVersion.requestCount, 1, "无 version：requests=1")

    // MARK: 8. version = 0.3.0 的 map 路径不变
    guard let mapVersion = ZedThreadParser.parse(threadJSON: Data(zedMapVersionJSON.utf8),
                                                 threadID: "th-map", updatedAtMs: 1) else {
        assertEqual(false, true, "0.3.0：应能解析")
        return
    }
    assertEqual(mapVersion.events.count, 1, "0.3.0：map 一条事件")
    assertEqual(mapVersion.usage, HarnessTokenUsage(uncachedInput: 100, output: 10,
                                                    cacheRead: 20, cacheWrite: 5, requestCount: 1),
                "0.3.0：四桶 100 / 10 / 20 / 5")
    assertEqual(mapVersion.appliedRemainder, false, "0.3.0：map 与累计相等，不补差额")

    // 形状兜底：version 声明新格式但数据是数组时仍按形状读（绝不整段判无效）
    let mismatched = """
{"version":"0.3.0","request_token_usage":[{"input_tokens":7,"output_tokens":1}],"cumulative_token_usage":{"input_tokens":7,"output_tokens":1}}
"""
    if let shapeFallback = ZedThreadParser.parse(threadJSON: Data(mismatched.utf8),
                                                 threadID: "th-mismatch", updatedAtMs: 1) {
        assertEqual(shapeFallback.events.count, 1, "形状兜底：版本与形状不一致时按形状读")
        assertEqual(shapeFallback.usage.uncachedInput, 7, "形状兜底：用量不丢")
    } else {
        assertEqual(false, true, "形状兜底：应能解析而不是判无效")
    }

    // MARK: 整库读取：旧库一行也能读出用量（data_type = json）
    let dbPath = tokenSourceTempDatabasePath("zed-legacy")
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    guard tokenSourceMakeSQLite(at: dbPath, statements: [
        "CREATE TABLE threads (id TEXT PRIMARY KEY, updated_at INTEGER, data_type TEXT, data BLOB);",
        "INSERT INTO threads (id, updated_at, data_type, data) VALUES "
            + "('th-legacy', 1767585600000, 'json', " + tokenSourceTextLiteral(zedLegacyVectorJSON) + ");",
    ]) else {
        assertEqual(false, true, "旧库：整库 fixture 建库失败")
        return
    }
    let read = ZedThreadParser.read(databaseAt: dbPath)
    assertEqual(read.isAvailable, true, "旧库整库：可读")
    assertEqual(read.events.count, 2, "旧库整库：两条事件")
    assertEqual(read.usage, legacy.usage, "旧库整库：与纯入口同口径")
    assertEqual(read.requestCount, 2, "旧库整库：requests=2")

    print("✅ Zed 旧库回归 works")
}
