import Foundation

// MARK: - Gemini CLI 会话解析

/// Gemini CLI 聊天记录解析（设计规格 §2.3）
///
/// 两种落盘形态共用同一个入口：
/// - **新版 JSONL**：一行一条记录 —— 消息记录 / 带 `messages` 的元信息记录 / `$set` 全量重写记录；
/// - **旧版整份 JSON**（`session-*.json`）：`messages` 数组一次给全。
/// 入口**先试整体解析、失败再逐行**，于是两种文件都能直接把内容喂进来。
///
/// 三个坑：
/// 1. `tokens` 可能为 null → 跳过该条（不补 0 记账）；
/// 2. `$set.messages` 是**全量重写** → 按消息 `id` 去重，同一 id 只算一次；
/// 3. 旧桶名是 project root 的 sha256，迁移会把同一份会话复制到新桶 → 同一份数据
///    可能出现两遍（扫描器按路径去重；这里再用 `(sessionId, id)` 兜底）。
public enum GeminiSessionParser {
    /// 该解析器负责的来源
    public static let source: TokenSourceID = .gemini
    /// Gemini CLI 只跑 Google 系模型，记录里不带 provider 字段，故按来源常量给
    public static let providerName = "google"
    /// 模型缺失时的兜底
    public static let unknownModel = "unknown"

    // MARK: - 入口

    /// 纯函数入口：整段文本（整份 JSON 或 JSONL 均可）
    public static func parse(text: String) -> TokenSourceParseReport {
        parse(data: Data(text.utf8))
    }

    /// 纯函数入口：整段字节
    public static func parse(data: Data) -> TokenSourceParseReport {
        var state = State()
        if let root = try? JSONSerialization.jsonObject(with: data) {
            state.consume(root)
        } else {
            state.consumeLines(data)
        }
        return state.report()
    }

    /// IO 入口：直接读文件（读不出来返回 nil → 调用方按可用性上报，不伪装成 0 用量）
    public static func parse(contentsOf url: URL) -> TokenSourceParseReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    // MARK: - 累计状态

    /// 解析过程中的累计状态（纯值类型：整份 JSON 与逐行两条路径共用同一套记账）
    struct State {
        var events: [TokenSourceUsageEvent] = []
        /// 当前生效的会话键（JSONL 首行的 `sessionId`）
        var sessionKey = ""
        /// 当前生效的项目根（记录里的 `.project_root`）
        var cwd = ""
        /// 当前生效的模型（记录上带 `model` 时随时更新）
        var model = ""
        /// 已计入的消息键（`sessionKey|id`；无 id 时退化为 `sessionKey|ts|四桶`）
        var seen: Set<String> = []
        var malformed = 0
        var ignored = 0
        var skipped = 0

        /// 吞一条已解析的 JSON 值（对象 = 一条记录；数组 = 一批消息）
        mutating func consume(_ any: Any) {
            if let record = TokenSourceJSON.object(any) {
                consumeRecord(record)
            } else if let array = any as? [Any] {
                consumeMessages(array)
            } else {
                malformed += 1
            }
        }

        /// 吞一条记录：`$set` 重写 / 容器 `messages` / 单条消息
        mutating func consumeRecord(_ record: [String: Any]) {
            applyMetadata(record)
            if let set = TokenSourceJSON.object(record["$set"]) {
                // 全量重写：把新值当消息继续解析，靠 id 去重保证不双算
                if let messages = set["messages"] {
                    consumeMessages(messages)
                } else {
                    ignored += 1
                }
                return
            }
            if let messages = record["messages"] {
                consumeMessages(messages)
                return
            }
            consumeMessage(record)
        }

        /// 逐行路径：一行一份 JSON（新版 JSONL）
        mutating func consumeLines(_ data: Data) {
            for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
                var line = rawLine
                if line.last == 0x0D { line = line.dropLast() }
                // 空行 / 纯空白不算坏行（与 Claude / Codex 同一口径）
                if TokenSourceJSON.isBlank(Data(line)) { continue }
                guard let record = TokenSourceJSON.object(from: Data(line)) else {
                    malformed += 1
                    continue
                }
                consumeRecord(record)
            }
        }

        /// 元信息：会话键 / 项目根 / 模型（消息记录上也带 `model`，随后生效）
        mutating func applyMetadata(_ record: [String: Any]) {
            if let id = TokenSourceJSON.string(record["sessionId"]) { sessionKey = id }
            if let root = TokenSourceJSON.string(record[".project_root"]) { cwd = root }
            if let name = TokenSourceJSON.string(record["model"]) { model = name }
        }

        /// 一批消息（`messages` / `$set.messages` 的元素）
        mutating func consumeMessages(_ any: Any?) {
            guard let any else { return }
            guard let list = any as? [Any] else {
                malformed += 1
                return
            }
            for element in list {
                guard let record = TokenSourceJSON.object(element) else {
                    malformed += 1
                    continue
                }
                consumeMessage(record)
            }
        }

        /// 单条消息：没有 `tokens` 或为 null 的（user / info / error）与统计无关
        mutating func consumeMessage(_ record: [String: Any]) {
            guard let rawTokens = record["tokens"], !(rawTokens is NSNull) else {
                ignored += 1
                return
            }
            guard let tokens = TokenSourceJSON.object(rawTokens) else {
                malformed += 1
                return
            }
            guard let tsMs = TokenSourceJSON.milliseconds(fromISO8601: record["timestamp"] as? String) else {
                malformed += 1
                return
            }
            if let name = TokenSourceJSON.string(record["model"]) { model = name }
            let usage = GeminiSessionParser.usage(from: tokens)
            guard !usage.isZero else {
                skipped += 1
                return
            }
            let key = dedupKey(record: record, tsMs: tsMs, usage: usage)
            guard !seen.contains(key) else {
                skipped += 1
                return
            }
            seen.insert(key)
            events.append(TokenSourceUsageEvent(
                source: GeminiSessionParser.source,
                tsMs: tsMs,
                provider: GeminiSessionParser.providerName,
                model: model.isEmpty ? GeminiSessionParser.unknownModel : model,
                usage: usage,
                sessionKey: sessionKey,
                cwd: cwd
            ))
        }

        /// 去重主键：消息 `id` 优先；缺失时退化为 (`sessionKey`, 时间戳, 四桶)
        func dedupKey(record: [String: Any], tsMs: Int64, usage: HarnessTokenUsage) -> String {
            if let id = TokenSourceJSON.string(record["id"]) { return sessionKey + "|" + id }
            return [
                "fallback", sessionKey, String(tsMs),
                String(usage.uncachedInput), String(usage.output), String(usage.cacheRead),
            ].joined(separator: "|")
        }

        /// 汇总成统一报告（会话元信息缺省为 nil，由扫描器用文件所属会话补齐）
        func report() -> TokenSourceParseReport {
            let hasSession = !sessionKey.isEmpty || !cwd.isEmpty || !model.isEmpty
            return TokenSourceParseReport(
                source: GeminiSessionParser.source,
                events: events,
                session: hasSession
                    ? TokenSourceSessionInfo(
                        source: GeminiSessionParser.source,
                        sessionKey: sessionKey,
                        cwd: cwd,
                        model: model.isEmpty ? GeminiSessionParser.unknownModel : model
                    )
                    : nil,
                ignoredLineCount: ignored,
                malformedLineCount: malformed,
                skippedLineCount: skipped
            )
        }
    }

    // MARK: - 四桶映射

    /// 四桶映射（规格 §2.7）：`uncachedInput = input - cached`（tool 计入输入）、
    /// `output = output + thoughts`、`cacheWrite = 0`（Gemini 不报缓存写入）
    static func usage(from tokens: [String: Any]) -> HarnessTokenUsage {
        let input = number(tokens, ["promptTokenCount", "input"])
        let cached = number(tokens, ["cachedContentTokenCount", "cached"])
        let output = number(tokens, ["candidatesTokenCount", "output"])
        /// thoughts 单列，必须加进 output（Gemini 的 reasoning 不计入 candidates）
        let thoughts = number(tokens, ["thoughtsTokenCount", "thoughts"])
        /// tool 用量不计入 promptTokenCount，单独并入输入
        let tool = number(tokens, ["toolUsePromptTokenCount", "tool"])
        return HarnessTokenUsage(
            uncachedInput: max(0, input - cached) + tool,
            output: output + thoughts,
            cacheRead: cached,
            cacheWrite: 0,
            requestCount: 1
        )
    }

    /// 上游两种命名都出现过（Gemini API 名 / 归一化名），两个都读、前者优先
    static func number(_ tokens: [String: Any], _ keys: [String]) -> Int {
        for key in keys {
            if let value = TokenSourceJSON.int(tokens[key]) { return TokenSourceJSON.nonNegative(value) }
        }
        return 0
    }
}
