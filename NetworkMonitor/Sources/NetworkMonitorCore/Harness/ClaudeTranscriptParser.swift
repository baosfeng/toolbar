import Foundation

// MARK: - Claude Code transcript 行解析

/// Claude Code transcript（`~/.claude/projects/<cwd>/<sessionId>.jsonl`）行解析器
///
/// 三条命门（不去重就是假数，实测虚高 1.96–2.6 倍）：
/// 1. **同一 `message.id` 多行只记一次**：一条 API 响应按 content block 拆成多行，
///    `usage` 逐字节相同；
/// 2. **`isSidechain` 副本丢弃**：子 agent 的重放行与父条目同 `message.id`、`requestId` 不同；
/// 3. **无 `message.id` 的退化行**按 (`sessionId`, `timestamp`, 四桶) 三元组去重。
///
/// 只认 `type == "assistant"` 且 `message.usage` 存在的行；其余一律 ignored。
/// 一个实例对应一个文件，换文件前调 `reset()`。
public final class ClaudeTranscriptParser: TokenLineParsing, @unchecked Sendable {
    /// Claude Code 只有 Anthropic 系模型，transcript 里不带 provider 字段，故按来源常量给
    public static let providerName = "anthropic"
    /// 模型缺失时的兜底
    public static let unknownModel = "unknown"

    public let source: TokenSourceID = .claudeCode

    /// 已计入的 `message.id`
    private var seenMessageIDs: Set<String> = []
    /// 无 `message.id` 时的退化去重键
    private var seenFallbackKeys: Set<String> = []

    public private(set) var malformedLineCount = 0
    public private(set) var ignoredLineCount = 0
    public private(set) var skippedLineCount = 0

    public init() {}

    /// 纯函数入口：整段文本 → 统一事件 + 计数（无需真实 CLI 安装，fixture 直接驱动）
    public static func parse(text: String) -> TokenSourceParseReport {
        TokenSourceParseRunner.run(text: text, through: ClaudeTranscriptParser())
    }

    public func reset() {
        seenMessageIDs.removeAll()
        seenFallbackKeys.removeAll()
        malformedLineCount = 0
        ignoredLineCount = 0
        skippedLineCount = 0
    }

    public func parse(line: Data) -> TokenSourceLineResult {
        guard !TokenSourceJSON.isBlank(line) else { return .ignored }
        guard let root = TokenSourceJSON.object(from: line) else {
            malformedLineCount += 1
            return .malformed("非 JSON 对象")
        }
        // 只处理 assistant：user / system / attachment / file-history-snapshot 等与用量无关
        guard TokenSourceJSON.string(root["type"]) == "assistant" else {
            ignoredLineCount += 1
            return .ignored
        }
        // sidechain 是子 agent 的重放副本，恒与父条目同 message.id，直接丢弃
        if TokenSourceJSON.bool(root["isSidechain"]) == true {
            skippedLineCount += 1
            return .ignored
        }
        let message = TokenSourceJSON.object(root["message"])
        guard let usageObject = TokenSourceJSON.object(message?["usage"]) else {
            ignoredLineCount += 1
            return .ignored
        }
        guard let tsMs = TokenSourceJSON.milliseconds(fromISO8601: root["timestamp"] as? String) else {
            malformedLineCount += 1
            return .malformed("assistant 行缺少可解析的 timestamp")
        }
        let sessionKey = TokenSourceJSON.string(root["sessionId"]) ?? ""
        let cwd = TokenSourceJSON.string(root["cwd"]) ?? ""
        let model = TokenSourceJSON.string(message?["model"]) ?? Self.unknownModel
        let usage = Self.usage(from: usageObject)

        guard let dedupKey = Self.dedupKey(message: message, sessionKey: sessionKey, tsMs: tsMs, usage: usage) else {
            malformedLineCount += 1
            return .malformed("assistant 行既无 message.id 也无可用去重键")
        }
        if dedupKey.isMessageID {
            if seenMessageIDs.contains(dedupKey.value) {
                skippedLineCount += 1
                return .ignored
            }
            seenMessageIDs.insert(dedupKey.value)
        } else {
            if seenFallbackKeys.contains(dedupKey.value) {
                skippedLineCount += 1
                return .ignored
            }
            seenFallbackKeys.insert(dedupKey.value)
        }

        return .usage(TokenSourceUsageEvent(
            source: source,
            tsMs: tsMs,
            provider: Self.providerName,
            model: model,
            usage: usage,
            sessionKey: sessionKey,
            cwd: cwd
        ))
    }

    // MARK: - 内部

    /// 去重键 + 是否 message.id 主键
    private struct DedupKey {
        let value: String
        let isMessageID: Bool
    }

    /// 主键取 `message.id`；缺失时退化为 (sessionId, timestamp, 四桶)
    private static func dedupKey(
        message: [String: Any]?,
        sessionKey: String,
        tsMs: Int64,
        usage: HarnessTokenUsage
    ) -> DedupKey? {
        if let id = TokenSourceJSON.string(message?["id"]) {
            return DedupKey(value: id, isMessageID: true)
        }
        // sessionId 与 timestamp 都没有时无法区分两条请求，只能判坏行
        guard !sessionKey.isEmpty, tsMs > 0 else { return nil }
        let value = [
            sessionKey,
            String(tsMs),
            String(usage.uncachedInput),
            String(usage.output),
            String(usage.cacheRead),
            String(usage.cacheWrite),
        ].joined(separator: "|")
        return DedupKey(value: value, isMessageID: false)
    }

    /// 四桶映射（Claude 的 input 不含缓存，与 DSH 同口径）
    private static func usage(from object: [String: Any]) -> HarnessTokenUsage {
        let uncachedInput = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["input_tokens"]) ?? 0)
        let output = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["output_tokens"]) ?? 0)
        let cacheRead = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cache_read_input_tokens"]) ?? 0)
        let cacheWrite = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cache_creation_input_tokens"]) ?? 0)
        return HarnessTokenUsage(
            uncachedInput: uncachedInput,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            requestCount: 1
        )
    }
}
