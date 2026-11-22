import Foundation
import NetworkMonitorCore

// MARK: - Codex rollout 解析器（设计规格 §2.2 / §7）
//
// fixture 全部自造：不读真实用户目录、不碰数据库。
// 覆盖：last_token_usage 优先 / 只有累计时的字段差分 / 累计回退不记负数 /
// fork 重放行跳过 / 老格式归无用量 / info 为 null 跳过。

// MARK: - fixture

/// C 组：last_token_usage 优先（cached ⊂ input，reasoning 已含在 output 里）
private let codexTranscriptC = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-c","cwd":"/tmp/proj-c","originator":"codex_cli_rs"}}
{"timestamp":"2026-01-05T10:00:01.000Z","type":"turn_context","payload":{"cwd":"/tmp/proj-c","model":"gpt-5.1-codex"}}
{"timestamp":"2026-01-05T10:00:15.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":125,"reasoning_output_tokens":75,"total_tokens":1125},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":250,"output_tokens":125},"model_context_window":272000}}}
"""

/// D 组：只有累计值（基线 0 / 差分 / 回退记 0 / 再差分）
private let codexTranscriptD = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-d","cwd":"/tmp/proj-d"}}
{"timestamp":"2026-01-05T10:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}}}
{"timestamp":"2026-01-05T10:00:20.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":100}}}}
{"timestamp":"2026-01-05T10:00:30.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":90,"output_tokens":20}}}}
{"timestamp":"2026-01-05T10:00:40.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":290,"output_tokens":105}}}}
"""

/// E 组：fork 重放行早于 session_meta（父会话时间戳）
private let codexTranscriptE = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-e","cwd":"/tmp/proj-e"}}
{"timestamp":"2026-01-05T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9999,"cached_input_tokens":0,"output_tokens":999}}}}
{"timestamp":"2026-01-05T10:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}
"""

/// F 组：老格式（无行包封、无 token_count）→ 归「该文件无用量」而不是错误
private let codexTranscriptF = """
{"id":"old-codex-1","timestamp":"2025-08-10T09:00:00.000Z","instructions":"be nice","cwd":"/tmp/old"}
{"type":"message","role":"user","content":[{"type":"input_text","text":"list the files here"}]}
"""

/// G 组：token_count 的 info 为 null → 跳过该行
private let codexTranscriptG = """
{"timestamp":"2026-01-05T10:00:00.000Z","type":"session_meta","payload":{"id":"cdx-g","cwd":"/tmp/proj-g"}}
{"timestamp":"2026-01-05T10:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}
{"timestamp":"2026-01-05T10:00:06.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}
"""

// MARK: - 套件

func runTokenSourceCodexParserTests() {
    print("🧪 Testing Codex rollout 解析（last 优先 / 累计差分 / 回退 / fork / 老格式）...")

    // C：last_token_usage 优先，cached 从 input 里扣、reasoning 不重复加
    let c = CodexRolloutParser.parse(text: codexTranscriptC)
    assertEqual(c.source, TokenSourceID.codex, "C：来源标识")
    assertEqual(c.events.count, 1, "C：事件数")
    assertEqual(c.usage.uncachedInput, 750, "C：uncached = input - cached")
    assertEqual(c.usage.output, 125, "C：output（reasoning 已含，不再相加）")
    assertEqual(c.usage.cacheRead, 250, "C：cacheRead = cached")
    assertEqual(c.usage.cacheWrite, 0, "C：Codex 不报缓存写入")
    assertEqual(c.usage.totalTokens, 1125, "C：四桶合计")
    assertEqual(c.malformedLineCount, 0, "C：无坏行")
    assertEqual(c.ignoredLineCount, 0, "C：无无关行")
    assertEqual(c.skippedLineCount, 0, "C：无丢弃")
    assertEqual(c.events.first?.provider, "openai", "C：provider 常量")
    assertEqual(c.events.first?.model, "gpt-5.1-codex", "C：模型取 turn_context.payload.model")
    assertEqual(c.events.first?.sessionKey, "cdx-c", "C：会话键取 session_meta.payload.id")
    assertEqual(c.events.first?.cwd, "/tmp/proj-c", "C：工作目录")
    assertEqual(c.session?.sessionKey, "cdx-c", "C：会话元信息")

    // D：只有累计值时按字段差分；回退记 0 且不产生负数
    let d = CodexRolloutParser.parse(text: codexTranscriptD)
    assertEqual(d.events.count, 2, "D：差分后事件数（首行无基线与回退均记 0）")
    assertEqual(d.usage.uncachedInput, 800, "D：uncached 合计")
    assertEqual(d.usage.output, 185, "D：output 合计")
    assertEqual(d.usage.cacheRead, 300, "D：cacheRead 合计")
    assertEqual(d.usage.cacheWrite, 0, "D：cacheWrite 恒 0")
    assertEqual(d.usage.totalTokens, 1285, "D：四桶合计")
    assertEqual(d.malformedLineCount, 0, "D：无坏行")
    assertEqual(d.ignoredLineCount, 0, "D：无无关行")
    assertEqual(d.skippedLineCount, 2, "D：首行无基线 + 累计回退各一次")
    assertEqual(d.events.first?.usage, HarnessTokenUsage(uncachedInput: 400, output: 100, cacheRead: 100, cacheWrite: 0, requestCount: 1), "D：第一次差分")
    assertEqual(d.events.last?.usage, HarnessTokenUsage(uncachedInput: 400, output: 85, cacheRead: 200, cacheWrite: 0, requestCount: 1), "D：回退后重新差分")
    let negatives = d.events.filter {
        $0.usage.uncachedInput < 0 || $0.usage.output < 0 || $0.usage.cacheRead < 0 || $0.usage.cacheWrite < 0
    }
    assertEqual(negatives.count, 0, "D：累计回退不记负数")

    // E：fork 重放行（时间戳早于 session_meta）跳过
    let e = CodexRolloutParser.parse(text: codexTranscriptE)
    assertEqual(e.events.count, 1, "E：重放行被丢弃")
    assertEqual(e.usage.uncachedInput, 100, "E：uncached")
    assertEqual(e.usage.output, 10, "E：output")
    assertEqual(e.usage.totalTokens, 110, "E：四桶合计")
    assertEqual(e.malformedLineCount, 0, "E：无坏行")
    assertEqual(e.ignoredLineCount, 0, "E：无无关行")
    assertEqual(e.skippedLineCount, 1, "E：fork 重放计数")

    // F：老格式无用量 → 零事件、不算错误
    let f = CodexRolloutParser.parse(text: codexTranscriptF)
    assertEqual(f.events.count, 0, "F：老格式零事件")
    assertEqual(f.hasUsage, false, "F：归为无用量")
    assertEqual(f.malformedLineCount, 0, "F：不算坏行")
    assertEqual(f.ignoredLineCount, 2, "F：两行都归 ignored")
    assertEqual(f.skippedLineCount, 0, "F：无丢弃")
    assertEqual(f.session, nil, "F：无会话元信息")

    // G：info 为 null → 跳过，不是坏行
    let g = CodexRolloutParser.parse(text: codexTranscriptG)
    assertEqual(g.events.count, 0, "G：零事件")
    assertEqual(g.malformedLineCount, 0, "G：不算坏行")
    assertEqual(g.ignoredLineCount, 2, "G：两行 token_count 都跳过")
    assertEqual(g.skippedLineCount, 0, "G：无丢弃")

    // reset：同一实例跨文件复用不串味
    let parser = CodexRolloutParser()
    _ = parser.parse(line: codexTranscriptD)
    parser.reset()
    let afterReset = parser.parse(line: """
{"timestamp":"2026-01-05T10:00:20.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":100}}}}
""")
    if case .ignored = afterReset {
        assertEqual(true, true, "reset：累计基线已清空（重新按无基线记 0）")
    } else {
        assertEqual("ignored", "其它", "reset：累计基线应已清空")
    }
    assertEqual(parser.skippedLineCount, 1, "reset：计数从零开始累计")
}

// MARK: - 端到端：单源 scoped 与来源识别

/// 解析报告 → bySource 计数（证明解析结果可直接喂给聚合层）
func runTokenSourceParsingBridgeTests() {
    print("🧪 Testing 解析结果 → 来源聚合桥接（口径一致）...")
    let claude = ClaudeTranscriptParser.parse(text: claudeTranscriptA)
    let codex = CodexRolloutParser.parse(text: codexTranscriptC)
    let claudeAggregate = HarnessSourceAggregate(
        allTime: claude.usage, today: claude.usage, thisWeek: claude.usage,
        daily: [], projects: [], models: [], indexedSessions: 1
    )
    let codexAggregate = HarnessSourceAggregate(
        allTime: codex.usage, today: codex.usage, thisWeek: codex.usage,
        daily: [], projects: [], models: [], indexedSessions: 1
    )
    let snapshot = HarnessUsageSnapshot(
        totals: HarnessUsageTotals(today: claude.usage.adding(codex.usage),
                                   thisWeek: claude.usage.adding(codex.usage),
                                   allTime: claude.usage.adding(codex.usage),
                                   cacheHitRate: nil),
        daily: [], projects: [], models: [],
        indexedSessions: 2, totalSessions: 2, lastScanAt: nil,
        indexingState: .ready, sourceAvailability: .available(toolPath: ""),
        perSourceAggregates: [.claudeCode: claudeAggregate, .codex: codexAggregate]
    )
    assertEqual(snapshot.bySource[.claudeCode]?.sessionCount, 1, "桥接：Claude 会话数")
    assertEqual(snapshot.bySource[.codex]?.usage.totalTokens, 1125, "桥接：Codex 四桶合计")
    assertEqual(TokenSourceScope.dataSources(in: snapshot), [TokenSourceID.claudeCode, TokenSourceID.codex], "桥接：两源均有数据")
    let scopedSum = snapshot.scoped(to: .claudeCode).totals.allTime
        .adding(snapshot.scoped(to: .codex).totals.allTime)
    assertEqual(scopedSum, snapshot.totals.allTime, "桥接：各源 scoped 之和 == 全量")
    print("✅ 解析结果 → 来源聚合桥接 works")
}
