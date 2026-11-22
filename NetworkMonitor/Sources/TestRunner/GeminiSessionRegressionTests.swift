import Foundation
import NetworkMonitorCore

// MARK: - Gemini 回归（$patch / $rewindTo / 重放 / chats 布局发现）
//
// 防复发：$patch 只改已有消息却被当新消息计一次 / $rewindTo 截断后仍保留被截记录（双计）/
// 同 id 回填再 append 被算两次 / 只按文件名前缀发现会整类漏掉 chats/<parentId>/ 下的子 agent。
// fixture 全部自造在 /tmp，不读真实 ~/.gemini。

/// 13：三条消息 + $rewindTo 截掉后两条 + $patch 改 m4 + m5 重放一次
private let geminiPatchRewindJSONL = """
{"sessionId":"g-reg","model":"gemini-2.5-pro"}
{"id":"m1","timestamp":"2026-01-05T10:00:00.000Z","tokens":{"promptTokenCount":100,"candidatesTokenCount":10}}
{"id":"m2","timestamp":"2026-01-05T10:00:10.000Z","tokens":{"promptTokenCount":200,"candidatesTokenCount":20}}
{"id":"m3","timestamp":"2026-01-05T10:00:20.000Z","tokens":{"promptTokenCount":300,"candidatesTokenCount":30}}
{"$rewindTo":"m2"}
{"id":"m4","timestamp":"2026-01-05T10:00:40.000Z","tokens":{"promptTokenCount":200,"candidatesTokenCount":20}}
{"$patch":{"id":"m4","tokens":{"promptTokenCount":300,"candidatesTokenCount":30}}}
{"id":"m5","timestamp":"2026-01-05T10:01:00.000Z","tokens":{"promptTokenCount":300,"candidatesTokenCount":30}}
{"id":"m5","timestamp":"2026-01-05T10:01:00.000Z","tokens":{"promptTokenCount":300,"candidatesTokenCount":30}}
"""

/// 14a：回填（$patch 补 output），单条消息只写一次
private let geminiBackfillJSONL = """
{"sessionId":"g-backfill"}
{"id":"m1","timestamp":"2026-01-05T10:00:00.000Z","tokens":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":10}}
{"$patch":{"id":"m1","tokens":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":12}}}
"""

/// 14b：回填后同 id 再 append —— 仍只算一次（不双计）
private let geminiBackfillReappendJSONL = """
{"sessionId":"g-backfill"}
{"id":"m1","timestamp":"2026-01-05T10:00:00.000Z","tokens":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":10}}
{"$patch":{"id":"m1","tokens":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":12}}}
{"id":"m1","timestamp":"2026-01-05T10:00:00.000Z","tokens":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":12}}
"""

func runGeminiSessionRegressionTests() {
    print("🧪 Testing Gemini 回归（$patch / $rewindTo / 重放 / chats 布局发现）...")

    // MARK: 13. $patch + $rewindTo + 重放
    let patched = GeminiSessionParser.parse(text: geminiPatchRewindJSONL)
    assertEqual(patched.events.count, 3, "补丁：m1 + m4 + m5 三条（被 $rewindTo 截掉的不算）")
    assertEqual(patched.usage.uncachedInput, 700, "补丁：uncached 700")
    assertEqual(patched.usage.output, 70, "补丁：output 70")
    assertEqual(patched.malformedLineCount, 0, "补丁：无坏行")
    assertEqual(patched.events.last?.tsMs, 1_767_607_260_000, "补丁：末条 ts = 1767607260000")
    assertEqual(patched.events.map(\.usage.uncachedInput), [100, 300, 300],
                "补丁：$patch 覆盖而不是追加（m4 = 300 而非 200+300）")
    assertEqual(patched.events.map(\.usage.output), [10, 30, 30],
                "补丁：重放的 m5 只保留一条")

    // MARK: 14. 回填：补丁补 output → 只算一次、skipped=0
    let backfill = GeminiSessionParser.parse(text: geminiBackfillJSONL)
    assertEqual(backfill.events.count, 1, "回填：单条消息只算一次")
    assertEqual(backfill.usage, HarnessTokenUsage(uncachedInput: 60, output: 12,
                                                  cacheRead: 40, cacheWrite: 0, requestCount: 1),
                "回填：四桶 60 / 12 / 40 / 0（补丁后的最终值）")
    assertEqual(backfill.skippedLineCount, 0, "回填：补丁不是「丢弃」，skipped 为 0")

    // 14b. 回填后同 id 再 append：用量仍只算一次（不双计）
    let reappend = GeminiSessionParser.parse(text: geminiBackfillReappendJSONL)
    assertEqual(reappend.events.count, 1, "再 append：同 id 仍只算一次")
    assertEqual(reappend.usage, HarnessTokenUsage(uncachedInput: 60, output: 12,
                                                  cacheRead: 40, cacheWrite: 0, requestCount: 1),
                "再 append：四桶不变（后者胜）")
    assertEqual(reappend.requestCount, 1, "再 append：requests 不翻倍")
    // 口径说明：两条都带 tokens 的重复 append 计入 skipped；作者表里的 skipped=0 对应
    // 「先 append tokens=null（ignored）再 append 带 tokens」的回填形态（该形态由
    // GeminiSessionParserTests 的 geminiBackfillJSONL 覆盖）。用量在两种形态下都不双计。
    assertEqual(reappend.skippedLineCount, 1, "再 append：重复 usage 行记 skipped=1（用量仍只算一次）")

    // MARK: 15. chats 布局发现：两个桶、父 + 子 agent、跨桶同名不误删、旧 .json 也收
    let root = tokenRegressionTempDirectory("gemini-chats")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let slugBucket = root + "/tmp/project-slug/chats"
    let legacyBucket = root + "/tmp/8f4c2a1d9e0b7a6c/chats"
    let sharedParentName = "session-2026-01-05T10-00-a1b2c3d4.jsonl"
    let sharedChildName = "session-child-1.jsonl"
    tokenRegressionWrite("{}", to: slugBucket + "/" + sharedParentName)
    tokenRegressionWrite("{}", to: slugBucket + "/session-2026-01-05T10-05-e5f6a7b8.json")
    tokenRegressionWrite("{}", to: slugBucket + "/parent-1/" + sharedChildName)
    tokenRegressionWrite("{}", to: slugBucket + "/parent-2/session-child-2.jsonl")
    tokenRegressionWrite("{}", to: legacyBucket + "/" + sharedParentName)
    tokenRegressionWrite("{}", to: legacyBucket + "/parent-1/" + sharedChildName)

    let candidates = HarnessDocumentChatLayout.candidates(roots: [URL(fileURLWithPath: root)])
    assertEqual(candidates.parentSessionFileCount, 3, "布局：收到 3 个父会话")
    assertEqual(candidates.subAgentFileCount, 3, "布局：收到 3 个子 agent（改前整类漏掉）")
    assertEqual(candidates.files.count, 6, "布局：共 6 个文件")
    assertEqual(candidates.buckets.count, 2, "布局：两个桶都扫到")
    assertEqual(candidates.droppedDuplicates, 0, "布局：跨桶同名文件不误删（按绝对路径去重）")
    assertEqual(candidates.files.filter { $0.url.path.hasSuffix(".json") }.count, 1,
                "布局：旧版整份 .json 也收")
    assertEqual(candidates.files.filter { $0.placement == .subAgent }
                    .allSatisfy { $0.url.path.contains("/chats/parent-") }, true,
                "布局：子 agent 归属按目录层级判")
    assertEqual(candidates.buckets.contains { $0.name.hasSuffix("project-slug") }, true,
                "布局：桶名按相对路径报（slug 桶）")
    assertEqual(candidates.buckets.contains { $0.name.hasSuffix("8f4c2a1d9e0b7a6c") }, true,
                "布局：桶名按相对路径报（旧 sha256 桶）")

    // 非 chats 结构（既无 chats 目录、也没有会话文件）→ 一个都不收
    let otherRoot = tokenRegressionTempDirectory("gemini-other")
    defer { try? FileManager.default.removeItem(atPath: otherRoot) }
    tokenRegressionWrite("notes", to: otherRoot + "/notes.txt")
    let otherCandidates = HarnessDocumentChatLayout.candidates(roots: [URL(fileURLWithPath: otherRoot)])
    assertEqual(otherCandidates.files.count, 0, "布局：非 chats 结构不收")
    assertEqual(otherCandidates.buckets.count, 0, "布局：非 chats 结构无桶")

    // 同根跑两次 → 全部按路径丢弃，不重复入库
    let twice = HarnessDocumentChatLayout.candidates(
        roots: [URL(fileURLWithPath: root), URL(fileURLWithPath: root)])
    assertEqual(twice.files.count, 6, "同根两次：文件数不翻倍")
    assertEqual(twice.droppedDuplicates, 6, "同根两次：dropped=6")

    // 文档级读取器：6 个文件 → 6 个扫描单元
    let reader = HarnessDocumentSourceReader()
    let discovered = reader.discover(source: .gemini, roots: [URL(fileURLWithPath: root)])
    assertEqual(discovered.files.count, 6, "读取器：6 个文件各成一个扫描单元")
    assertEqual(discovered.files.allSatisfy { $0.path.contains("#") }, true,
                "读取器：单元键是 <文件>#<会话键>")

    print("✅ Gemini 回归 works")
}
