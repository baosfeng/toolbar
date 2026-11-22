import Foundation
import NetworkMonitorCore

// MARK: - Claude Code transcript 解析器（设计规格 §2.1 / §7）
//
// fixture 全部自造：不读真实用户目录、不碰数据库。
// 覆盖：同 message.id 多行只算一次 / isSidechain 副本丢弃 / 无 message.id 的三元组去重 /
// 坏行只计数不中断 / message.usage 缺失归 ignored / 数字字符串宽松读取。

// MARK: - fixture

/// A 组：同一条响应的三行（第三行是 sidechain 副本）+ user 行 + 坏行
///
/// 放宽为 internal（不加 private）：桥接套件 `runTokenSourceParsingBridgeTests`
/// 在另一个文件里复用同一份 fixture。
let claudeTranscriptA = """
{"type":"user","message":{"role":"user"},"timestamp":"2026-01-05T10:00:00.000Z","sessionId":"s-a","cwd":"/tmp/proj-a"}
{"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_a1","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":2000,"cache_creation_input_tokens":3000}},"requestId":"req_1","timestamp":"2026-01-05T10:00:05.000Z","sessionId":"s-a","cwd":"/tmp/proj-a"}
{"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_a1","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":2000,"cache_creation_input_tokens":3000}},"requestId":"req_1","timestamp":"2026-01-05T10:00:05.000Z","sessionId":"s-a","cwd":"/tmp/proj-a"}
{"type":"assistant","isSidechain":true,"message":{"model":"claude-sonnet-4-6","id":"msg_a1","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":2000,"cache_creation_input_tokens":3000}},"requestId":"req_2","timestamp":"2026-01-05T10:00:05.000Z","sessionId":"s-a","cwd":"/tmp/proj-a"}
{this line is intentionally malformed json
{"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_a2","usage":{"input_tokens":200,"output_tokens":100}},"timestamp":"2026-01-05T10:00:10.000Z","sessionId":"s-a","cwd":"/tmp/proj-a"}
"""

/// B 组：没有 message.id（按 sessionId + timestamp + 四桶三元组去重），四桶是数字字符串
private let claudeTranscriptB = """
{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":"10","output_tokens":"1","cache_read_input_tokens":"0","cache_creation_input_tokens":"0"}},"timestamp":"2026-01-05T11:00:00.000Z","sessionId":"s-b","cwd":"/tmp/proj-b"}
{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":"10","output_tokens":"1","cache_read_input_tokens":"0","cache_creation_input_tokens":"0"}},"timestamp":"2026-01-05T11:00:00.000Z","sessionId":"s-b","cwd":"/tmp/proj-b"}
"""

/// 坏行在前、正常行在后：证明坏行不吞噬后续行
private let claudeBadLineFirst = """
{not json at all}
{"type":"assistant","message":{"id":"msg_x","usage":{"input_tokens":5,"output_tokens":2}},"timestamp":"2026-01-05T12:00:00.000Z","sessionId":"s-x"}
"""

/// assistant 行但没有 message.usage：与统计无关，归 ignored（不是坏行）
private let claudeMissingUsage = """
{"type":"assistant","message":{"model":"m","id":"msg_no_usage"},"timestamp":"2026-01-05T12:00:00.000Z","sessionId":"s-n"}
{"type":"assistant","message":{"id":"msg_with_usage","usage":{"input_tokens":7,"output_tokens":3}},"timestamp":"2026-01-05T12:00:01.000Z","sessionId":"s-n"}
"""

// MARK: - 套件

func runTokenSourceClaudeParserTests() {
    print("🧪 Testing Claude Code transcript 解析（去重 / sidechain / 坏行 / 宽松读取）...")

    // A 组：三行同 message.id 只算一次，sidechain 副本与重复行计入 skipped
    let a = ClaudeTranscriptParser.parse(text: claudeTranscriptA)
    assertEqual(a.source, TokenSourceID.claudeCode, "A：来源标识")
    assertEqual(a.events.count, 2, "A：去重后事件数")
    assertEqual(a.usage.uncachedInput, 1200, "A：uncached 合计")
    assertEqual(a.usage.output, 600, "A：output 合计")
    assertEqual(a.usage.cacheRead, 2000, "A：cacheRead 合计")
    assertEqual(a.usage.cacheWrite, 3000, "A：cacheWrite 合计")
    assertEqual(a.usage.totalTokens, 6800, "A：四桶合计")
    assertEqual(a.requestCount, 2, "A：请求数")
    assertEqual(a.malformedLineCount, 1, "A：坏行计数")
    assertEqual(a.ignoredLineCount, 1, "A：无关行计数（user 行）")
    assertEqual(a.skippedLineCount, 2, "A：去重丢弃（重复 + sidechain）")
    assertEqual(a.events.first?.provider, "anthropic", "A：provider 常量")
    assertEqual(a.events.first?.model, "claude-sonnet-4-6", "A：模型取自 message.model")
    assertEqual(a.events.first?.sessionKey, "s-a", "A：会话键")
    assertEqual(a.events.first?.cwd, "/tmp/proj-a", "A：工作目录")
    assertEqual(a.events.last?.model, "claude-sonnet-4-6", "A：第二条事件的模型")
    assertEqual((a.events.first?.tsMs ?? 0) < (a.events.last?.tsMs ?? 0), true, "A：事件按时间升序")
    assertEqual((a.events.first?.tsMs ?? 0) > 1_700_000_000_000, true, "A：ISO8601 → epoch 毫秒")

    // B 组：无 message.id 退化去重，数字字符串照读
    let b = ClaudeTranscriptParser.parse(text: claudeTranscriptB)
    assertEqual(b.events.count, 1, "B：三元组去重后事件数")
    assertEqual(b.usage.uncachedInput, 10, "B：uncached")
    assertEqual(b.usage.output, 1, "B：output")
    assertEqual(b.usage.cacheRead, 0, "B：cacheRead")
    assertEqual(b.usage.cacheWrite, 0, "B：cacheWrite")
    assertEqual(b.usage.totalTokens, 11, "B：四桶合计")
    assertEqual(b.malformedLineCount, 0, "B：无坏行")
    assertEqual(b.ignoredLineCount, 0, "B：无无关行")
    assertEqual(b.skippedLineCount, 1, "B：重复行被丢弃")
    assertEqual(b.session, nil, "B：Claude 不产出会话元信息")

    // 坏行不影响后续行
    let badFirst = ClaudeTranscriptParser.parse(text: claudeBadLineFirst)
    assertEqual(badFirst.malformedLineCount, 1, "坏行：计数")
    assertEqual(badFirst.events.count, 1, "坏行：后续正常行仍计入")
    assertEqual(badFirst.usage.uncachedInput, 5, "坏行：后续行用量正确")
    assertEqual(badFirst.events.first?.model, "unknown", "缺模型：兜底 unknown")
    assertEqual(badFirst.events.first?.provider, "anthropic", "缺模型：provider 仍按来源常量")

    // message.usage 缺失 → ignored，且不打断下一条
    let missingUsage = ClaudeTranscriptParser.parse(text: claudeMissingUsage)
    assertEqual(missingUsage.events.count, 1, "缺 usage：只算有 usage 的那行")
    assertEqual(missingUsage.ignoredLineCount, 1, "缺 usage：归 ignored")
    assertEqual(missingUsage.malformedLineCount, 0, "缺 usage：不算坏行")

    // reset 后计数与去重集合归零（同一实例跨文件复用）
    let parser = ClaudeTranscriptParser()
    _ = parser.parse(line: claudeTranscriptA)
    parser.reset()
    assertEqual(parser.malformedLineCount, 0, "reset：坏行计数清零")
    assertEqual(parser.skippedLineCount, 0, "reset：去重计数清零")
    let replayed = parser.parse(line: """
{"type":"assistant","message":{"id":"msg_a1","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":2000,"cache_creation_input_tokens":3000}},"timestamp":"2026-01-05T10:00:05.000Z","sessionId":"s-a"}
""")
    if case .usage = replayed {
        assertEqual(true, true, "reset：去重集合已清空，同 id 可再次计入")
    } else {
        assertEqual("usage", "非 usage", "reset：去重集合应已清空")
    }

    print("✅ Claude transcript 解析 works")
}
