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

    print("✅ Gemini 会话解析 works")
}
