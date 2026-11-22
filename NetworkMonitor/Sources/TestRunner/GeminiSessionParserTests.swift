import Foundation
import NetworkMonitorCore

// MARK: - Gemini CLI 会话解析（设计规格 §2.3 / §7）
//
// 两种落盘形态共用 `parse(text:)` / `parse(data:)`：新版 JSONL 与旧版整份 JSON。
// fixture 全部自造在代码里，不读真实用户目录。
// 覆盖：JSONL 去重（$set 全量重写）/ tokens=null / 整份 JSON / 未知行 / 坏行 / IO 入口。

/// JSONL 形态：2 条用量消息（uncached 1155 / output 650 / cacheRead 300）
private let geminiJSONL = """
{"sessionId":"g-1",".project_root":"/tmp/gemini-proj","model":"gemini-2.5-pro"}
{"type":"user","content":"hi"}
{"type":"info","timestamp":"2026-01-05T10:00:02.000Z","tokens":null}
{"id":"m1","timestamp":"2026-01-05T10:00:05.000Z","tokens":{"promptTokenCount":1000,"cachedContentTokenCount":300,"candidatesTokenCount":500,"thoughtsTokenCount":100,"toolUsePromptTokenCount":55}}
{"$set":{"messages":[{"id":"m1","timestamp":"2026-01-05T10:00:05.000Z","tokens":{"promptTokenCount":1000,"cachedContentTokenCount":300,"candidatesTokenCount":500,"thoughtsTokenCount":100,"toolUsePromptTokenCount":55}}]}}
{"id":"m2","timestamp":"2026-01-05T10:00
{"id":"m2","timestamp":"2026-01-05T10:00:10.000Z","tokens":{"promptTokenCount":400,"candidatesTokenCount":50}}
"""

/// 整份 JSON 形态（旧版 `session-*.json`）
private let geminiWholeJSON = """
{"sessionId":"g-json",".project_root":"/tmp/gemini-json","model":"gemini-2.5-flash","messages":[
{"id":"a1","timestamp":"2026-01-05T11:00:00.000Z","tokens":{"promptTokenCount":200,"cachedContentTokenCount":100,"candidatesTokenCount":50,"thoughtsTokenCount":5}},
{"id":"a2","timestamp":"2026-01-05T11:00:05.000Z","tokens":{"promptTokenCount":110}},
{"id":"a3","timestamp":"2026-01-05T11:00:10.000Z","tokens":null}]}
"""


/// 新补丁形态：$patch 只改已有消息、$rewindTo 截断、同 id 再 append 后者胜
private let geminiPatchJSONL = """
{"sessionId":"g-2",".project_root":"/tmp/gemini-patch","model":"gemini-2.5-pro"}
{"id":"p1","timestamp":"2026-01-05T10:00:00.000Z","tokens":{"promptTokenCount":100,"candidatesTokenCount":10}}
{"id":"p2","timestamp":"2026-01-05T10:00:10.000Z","tokens":{"promptTokenCount":200,"candidatesTokenCount":20}}
{"id":"p3","timestamp":"2026-01-05T10:00:20.000Z","tokens":{"promptTokenCount":300,"candidatesTokenCount":30}}
{"$patch":{"id":"p1","content":[{"text":"x"}]}}
{"$rewindTo":"p3"}
{"id":"p3","timestamp":"2026-01-05T10:01:00.000Z","tokens":{"promptTokenCount":400,"candidatesTokenCount":40}}
"""

/// recordMessageTokens 回填形态：先 append 一条 tokens=null 的同 id 记录，再 append 带 tokens 的
private let geminiBackfillJSONL = """
{"sessionId":"g-3",".project_root":"/tmp/gemini-backfill","model":"gemini-2.5-pro"}
{"id":"b1","timestamp":"2026-01-05T10:00:00.000Z","type":"gemini","tokens":null}
{"id":"b1","timestamp":"2026-01-05T10:00:00.000Z","type":"gemini","tokens":{"promptTokenCount":100,"cachedContentTokenCount":40,"candidatesTokenCount":5,"thoughtsTokenCount":7}}
"""

func runGeminiSessionParserTests() {
    print("🧪 Testing Gemini 会话解析（JSONL / 整份 JSON / 去重 / tokens=null）...")

    // MARK: JSONL 形态
    let jsonl = GeminiSessionParser.parse(text: geminiJSONL)
    assertEqual(jsonl.source, TokenSourceID.gemini, "JSONL：来源标识")
    assertEqual(jsonl.events.count, 2, "JSONL：两条用量消息（$set 重复 id 只算一次）")
    assertEqual(jsonl.requestCount, 2, "JSONL：请求数")
    assertEqual(jsonl.usage.uncachedInput, 1155, "JSONL：uncached（input-cached + tool）")
    assertEqual(jsonl.usage.output, 650, "JSONL：output（含 thoughts）")
    assertEqual(jsonl.usage.cacheRead, 300, "JSONL：cacheRead")
    assertEqual(jsonl.usage.cacheWrite, 0, "JSONL：cacheWrite 恒 0")
    assertEqual(jsonl.malformedLineCount, 1, "JSONL：截断行计入 malformed")
    assertEqual(jsonl.ignoredLineCount, 3, "JSONL：元信息行 / user 行 / tokens=null 各一条")
    assertEqual(jsonl.skippedLineCount, 1, "JSONL：重复 id 计入 skipped")
    assertEqual(jsonl.events.first?.provider, "google", "JSONL：provider 常量")
    assertEqual(jsonl.events.first?.model, "gemini-2.5-pro", "JSONL：模型取自元信息行")
    assertEqual(jsonl.events.first?.sessionKey, "g-1", "JSONL：会话键")
    assertEqual(jsonl.events.first?.cwd, "/tmp/gemini-proj", "JSONL：项目根")
    assertEqual(jsonl.events.first?.usage,
                HarnessTokenUsage(uncachedInput: 755, output: 600, cacheRead: 300,
                                  cacheWrite: 0, requestCount: 1), "JSONL：首条四桶")
    assertEqual(jsonl.events.last?.usage,
                HarnessTokenUsage(uncachedInput: 400, output: 50, cacheRead: 0,
                                  cacheWrite: 0, requestCount: 1), "JSONL：次条四桶")
    assertEqual((jsonl.events.first?.tsMs ?? 0) > 1_700_000_000_000, true, "JSONL：时间戳为 epoch 毫秒")
    assertEqual(jsonl.session?.sessionKey, "g-1", "JSONL：会话元信息")

    // MARK: 整份 JSON 形态
    let whole = GeminiSessionParser.parse(text: geminiWholeJSON)
    assertEqual(whole.events.count, 2, "整份 JSON：两条用量消息")
    assertEqual(whole.requestCount, 2, "整份 JSON：请求数")
    assertEqual(whole.usage.uncachedInput, 210, "整份 JSON：uncached")
    assertEqual(whole.usage.output, 55, "整份 JSON：output")
    assertEqual(whole.usage.cacheRead, 100, "整份 JSON：cacheRead")
    assertEqual(whole.usage.cacheWrite, 0, "整份 JSON：cacheWrite")
    assertEqual(whole.ignoredLineCount, 1, "整份 JSON：tokens=null 记 ignored")
    assertEqual(whole.malformedLineCount, 0, "整份 JSON：无坏行")
    assertEqual(whole.skippedLineCount, 0, "整份 JSON：无丢弃")
    assertEqual(whole.session?.cwd, "/tmp/gemini-json", "整份 JSON：项目根")
    assertEqual(whole.events.first?.model, "gemini-2.5-flash", "整份 JSON：模型")

    // MARK: 两种入口等价 + IO 入口
    assertEqual(GeminiSessionParser.parse(data: Data(geminiJSONL.utf8)), jsonl, "入口：data 与 text 等价")
    let tempPath = NSTemporaryDirectory() + "gemini-session-" + UUID().uuidString + ".jsonl"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }
    if (try? Data(geminiJSONL.utf8).write(to: URL(fileURLWithPath: tempPath))) != nil {
        assertEqual(GeminiSessionParser.parse(contentsOf: URL(fileURLWithPath: tempPath)), jsonl,
                    "入口：读文件与直喂文本等价")
    } else {
        assertEqual(false, true, "入口：临时文件写入失败")
    }
    assertEqual(GeminiSessionParser.parse(contentsOf: URL(fileURLWithPath: tempPath + ".missing")) == nil,
                true, "入口：文件不可读返回 nil（不伪装成 0 用量）")

    // MARK: 空内容 / 空行
    let empty = GeminiSessionParser.parse(text: "")
    assertEqual(empty.events.count, 0, "空内容：零事件")
    assertEqual(empty.malformedLineCount, 0, "空内容：空行不算坏行")

    // MARK: $patch / $rewindTo / 同 id 再 append（新版 append-only 记录）
    let patched = GeminiSessionParser.parse(text: geminiPatchJSONL)
    assertEqual(patched.events.count, 3, "$rewindTo：截断后重生成的 p3 只留最新一条，共 3 条事件")
    assertEqual(patched.usage.uncachedInput, 700, "截断：uncached 100+200+400=700（被截断的 300 不计）")
    assertEqual(patched.usage.output, 70, "截断：output 10+20+40=70（被截断的 30 不计）")
    assertEqual(patched.requestCount, 3, "截断：请求数 3")
    assertEqual(patched.skippedLineCount, 2, "截断与重放各计 skipped=1")
    assertEqual(patched.ignoredLineCount, 2, "元信息行与无用量影响的 $patch 计 ignored")
    assertEqual(patched.events.map(\.tsMs).last, 1_767_607_260_000, "重生成的 p3 用新时间戳")

    let backfill = GeminiSessionParser.parse(text: geminiBackfillJSONL)
    assertEqual(backfill.events.count, 1, "回填：同 id 再 append 只留一条事件")
    assertEqual(backfill.usage, HarnessTokenUsage(uncachedInput: 60, output: 12, cacheRead: 40,
                                                  cacheWrite: 0, requestCount: 1),
                "回填：后者胜 —— uncached 60 / output 5+7=12 / cacheRead 40")
    assertEqual(backfill.skippedLineCount, 0, "回填：首条 tokens=null 未计入用量，重复 id 不重复计请求")
    assertEqual(backfill.ignoredLineCount, 2, "回填：元信息行 + tokens=null 各计 ignored")

    print("✅ Gemini 会话解析 works")
}
