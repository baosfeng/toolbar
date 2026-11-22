import Foundation
import NetworkMonitorCore

// MARK: - Codex 回归（上游源码核实后修掉的 5 类缺陷）
//
// 防复发：冷会话 .jsonl.zst 漏扫 / token_usage_record 与 token_count 双算 /
// cache_write_input_tokens 丢列 / 未知 type 当坏行 / 同一 rollout 三份副本重复计。
// fixture 全部自造在 /tmp，不读真实 ~/.codex。

// MARK: - 共享夹具辅助（本轮回归测试共用）

/// 静默日志（扫描器要 logger，但不验证日志）
final class TokenSourceTestLogger: LoggingService, @unchecked Sendable {
    func log(_ level: LogLevel, _ message: String) {}
}

/// 独立临时目录（每个用例一份，结尾自行删除）
func tokenRegressionTempDirectory(_ name: String) -> String {
    let path = NSTemporaryDirectory() + "token-regression-" + name + "-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

/// 写文本文件（自动建父目录）；成功返回 true
@discardableResult
func tokenRegressionWrite(_ text: String, to path: String) -> Bool {
    let directory = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    return (try? Data(text.utf8).write(to: URL(fileURLWithPath: path))) != nil
}

/// 把一段 JSONL 压成 .zst（系统 zstd 不可用返回 nil，调用方跳过并打印）
func tokenRegressionZstdArchive(_ text: String, at archivePath: String, zstdPath: String) -> Bool {
    let plain = archivePath + ".plain"
    guard tokenRegressionWrite(text, to: plain) else { return false }
    defer { try? FileManager.default.removeItem(atPath: plain) }
    try? FileManager.default.createDirectory(
        atPath: (archivePath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
    return harnessCompress(zstdPath: zstdPath, from: plain, to: archivePath)
}

// MARK: - fixture

/// 权威用量 + 两条 token_count 并存（同一响应的三种写法）
private let codexCoexistFixture = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-1","cwd":"/tmp/cdx"}}
{"timestamp":"2026-01-05T10:00:05.000Z","type":"token_usage_record","payload":{"response_id":"resp-1","thread_id":"cdx-1","usage":{"input_tokens":1100,"cached_input_tokens":300,"cache_write_input_tokens":50,"output_tokens":700,"reasoning_output_tokens":100}}}
{"timestamp":"2026-01-05T10:00:06.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1100,"cached_input_tokens":300,"cache_write_input_tokens":50,"output_tokens":700}}}}
{"timestamp":"2026-01-05T10:00:07.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1100,"cached_input_tokens":300,"cache_write_input_tokens":50,"output_tokens":700}}}}
"""

/// 同一 response_id 被重放（resume / fork）
private let codexReplayFixture = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-2","cwd":"/tmp/cdx"}}
{"timestamp":"2026-01-05T10:00:05.000Z","type":"token_usage_record","payload":{"response_id":"resp-9","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}
{"timestamp":"2026-01-05T10:00:06.000Z","type":"token_usage_record","payload":{"response_id":"resp-9","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}
"""

/// 未知 type（上游会持续新增变体）+ 白名单里与用量无关的 type
private let codexUnknownTypeFixture = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-3"}}
{"timestamp":"2026-01-05T10:00:01.000Z","type":"brand_new_variant","payload":{}}
{"timestamp":"2026-01-05T10:00:02.000Z","type":"response_item","payload":{}}
"""

/// 一条会话的 rollout 内容（冷会话压缩 / 副本去重都用它）
private let codexRolloutBody = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"threadA","cwd":"/tmp/cdx-a"}}
{"timestamp":"2026-01-05T10:00:05.000Z","type":"token_usage_record","payload":{"response_id":"r-a1","usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":30}}}
"""

// MARK: - 套件

func runCodexSourceRegressionTests() {
    print("🧪 Testing Codex 回归（zst 冷会话 / 双算 / cacheWrite / 未知 type / 副本去重）...")

    // MARK: 1. token_usage_record 与 token_count 并存：按响应去重，绝不相加
    let coexist = CodexRolloutParser.parse(text: codexCoexistFixture)
    assertEqual(coexist.events.count, 1, "并存：只算一次（记录优先，token_count 不相加）")
    assertEqual(coexist.usage, HarnessTokenUsage(uncachedInput: 800, output: 700,
                                                 cacheRead: 300, cacheWrite: 50, requestCount: 1),
                "并存：四桶 800 / 300 / 700 / 50")
    assertEqual(coexist.malformedLineCount, 0, "并存：无坏行")
    assertEqual(coexist.skippedLineCount, 2, "并存：两条 token_count 计 skipped=2")
    assertEqual(coexist.events.first?.provider, "openai", "并存：provider 常量")

    // MARK: 3. cache_write_input_tokens 映射进 cacheWrite（改前恒 0）
    assertEqual(coexist.usage.cacheWrite, 50, "cacheWrite：token_usage_record 的 cache_write_input_tokens 计入")

    // MARK: 2b. 同一 response_id 重放只算一次
    let replay = CodexRolloutParser.parse(text: codexReplayFixture)
    assertEqual(replay.events.count, 1, "重放：同 response_id 只算一次")
    assertEqual(replay.skippedLineCount, 1, "重放：第二条计 skipped")
    assertEqual(replay.usage.uncachedInput, 100, "重放：用量不翻倍")

    // MARK: 4. 未知 type 不再当坏行
    let unknown = CodexRolloutParser.parse(text: codexUnknownTypeFixture)
    assertEqual(unknown.malformedLineCount, 0, "未知 type：不计 malformed")
    assertEqual(unknown.ignoredLineCount, 2, "未知 type：与无关行一起归 ignored")
    assertEqual(unknown.events.count, 0, "未知 type：零事件")
    let probe = CodexRolloutParser()
    _ = probe.parse(line: Data("{\"type\":\"brand_new_variant\"}".utf8))
    assertEqual(probe.unknownTypeLineCount, 1, "未知 type：unknownTypeLineCount +1")
    let knownProbe = CodexRolloutParser()
    _ = knownProbe.parse(line: Data("{\"type\":\"response_item\"}".utf8))
    assertEqual(knownProbe.unknownTypeLineCount, 0, "白名单内 type：不计 unknownType")

    // MARK: 1. 冷会话 *.jsonl.zst 能被发现（并解压后扫出事件）
    guard let zstd = harnessZstdPath() else {
        print("⏭ zstd 可执行文件不可用，跳过冷会话 .jsonl.zst 的发现与解压用例")
        print("✅ Codex 回归 works")
        return
    }
    let home = tokenRegressionTempDirectory("codex-home")
    defer { try? FileManager.default.removeItem(atPath: home) }
    let dayDirectory = home + "/sessions/2026/01/01"
    let coldA = dayDirectory + "/rollout-2026-01-01T00-00-00-threadA.jsonl.zst"
    let coldB = dayDirectory + "/rollout-2026-01-01T00-00-00-threadB.jsonl.zst"
    let compressedA = tokenRegressionZstdArchive(codexRolloutBody, at: coldA, zstdPath: zstd)
    let compressedB = tokenRegressionZstdArchive(codexRolloutBody, at: coldB, zstdPath: zstd)
    assertEqual(compressedA && compressedB, true, "冷会话：两份 .jsonl.zst 压缩完成")

    let storage = InMemoryStorage()
    let environment = ["CODEX_HOME": home]
    let discovery = HarnessSourceDiscovery.report(source: .codex, storage: storage,
                                                 environment: environment)
    assertEqual(discovery.files.count, 2, "冷会话：发现 2 个扫描单元（改前按 .jsonl 匹配得 0）")
    assertEqual(discovery.droppedDuplicateSessions, 0, "冷会话：无重复丢弃")
    assertEqual(discovery.files.allSatisfy { $0.path.hasSuffix(".jsonl.zst") }, true,
                "冷会话：路径都是 .jsonl.zst")
    assertEqual(discovery.files.map(\.sessionID).sorted(),
                ["rollout-2026-01-01T00-00-00-threadA", "rollout-2026-01-01T00-00-00-threadB"],
                "冷会话：会话 id 去掉 .zst 后与明文同形")
    // 解压路径：扫一次该单元必须真的读出事件
    let scanner = HarnessMultiSourceScanner(storage: storage, logger: TokenSourceTestLogger(),
                                            environment: environment)
    let coldFile = discovery.files.first { $0.path.hasSuffix("threadA.jsonl.zst") }
    if let coldFile, let scanned = try? scanner.scan(file: coldFile,
                                                     isCancelled: { false }, onLinesRead: nil) {
        assertEqual(scanned.events.count, 1, "冷会话：解压后可扫出事件（改前 0 事件）")
        assertEqual(scanned.events.first?.usage.uncachedInput, 300, "冷会话：解压后四桶正确")
        assertEqual(scanned.malformedLines, 0, "冷会话：解压后无坏行")
    } else {
        assertEqual(false, true, "冷会话：.jsonl.zst 单元扫描失败")
    }

    // MARK: 5. 明文 + .zst + 归档副本：只算 1 单元、活跃副本（明文）优先
    let dedupeHome = tokenRegressionTempDirectory("codex-dedupe")
    defer { try? FileManager.default.removeItem(atPath: dedupeHome) }
    let dedupeDay = "2026/01/01"
    let plainActive = dedupeHome + "/sessions/" + dedupeDay + "/rollout-2026-01-01T00-00-00-threadC.jsonl"
    let compressedSame = plainActive + ".zst"
    let plainArchived = dedupeHome + "/archived_sessions/" + dedupeDay
        + "/rollout-2026-01-01T00-00-00-threadC.jsonl"
    tokenRegressionWrite(codexRolloutBody, to: plainActive)
    tokenRegressionWrite(codexRolloutBody, to: plainArchived)
    _ = tokenRegressionZstdArchive(codexRolloutBody, at: compressedSame, zstdPath: zstd)

    let dedupe = HarnessSourceDiscovery.report(source: .codex, storage: InMemoryStorage(),
                                              environment: ["CODEX_HOME": dedupeHome])
    assertEqual(dedupe.files.count, 1, "去重：同一 rollout 三份副本只算 1 单元")
    assertEqual(dedupe.droppedDuplicateSessions, 2, "去重：丢弃 2 份")
    // 临时目录经 /var → /private/var 软链，按后缀比对（绝对路径前缀随系统解析变化）
    assertEqual(dedupe.files.first?.path.hasSuffix(
        "/sessions/2026/01/01/rollout-2026-01-01T00-00-00-threadC.jsonl"), true,
        "去重：保留活跃根（sessions/）下的明文副本")
    assertEqual(dedupe.files.first?.path.contains("/archived_sessions/"), false,
                "去重：归档副本不被选中")
    assertEqual(dedupe.files.first?.path.hasSuffix(".zst"), false, "去重：明文优先于压缩件")

    print("✅ Codex 回归 works")
}
