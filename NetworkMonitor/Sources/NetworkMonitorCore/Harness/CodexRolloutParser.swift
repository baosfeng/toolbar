import Foundation

// MARK: - Codex CLI rollout 行解析

/// Codex CLI rollout（`$CODEX_HOME/sessions/.../rollout-*.jsonl`）行解析器
///
/// 口径要点：
/// - **`cached_input_tokens` 是 `input_tokens` 的子集** → `uncachedInput = input - cached`；
///   `cacheRead = cached`、`cacheWrite = 0`（Codex 不报缓存写入）；
/// - **`reasoning_output_tokens` 已含在 `output_tokens` 里**，不再相加；
/// - `last_token_usage` 优先；只有 `total_token_usage` 时按字段差分；
/// - **累计回退**（compaction / fork / 陈旧快照）重设基线、本次记 0，绝不记负数；
/// - fork 会话会在文件头重放父会话的 `token_count` 行（时间戳早于本文件 `session_meta`）→ 跳过；
/// - 老格式（2025-09-06 之前）没有行包封、没有 `token_count` → 全部 ignored，
///   归为「该文件无用量」而不是错误。
///
/// 一个实例对应一个文件，换文件前调 `reset()`。
public final class CodexRolloutParser: TokenLineParsing, @unchecked Sendable {
    /// Codex CLI 跑 OpenAI 系模型，rollout 里不带 provider 字段，故按来源常量给
    public static let providerName = "openai"
    /// 模型缺失时的兜底
    public static let unknownModel = "unknown"

    public let source: TokenSourceID = .codex

    /// 当前生效的会话键（`session_meta.payload.id`）
    private var sessionKey = ""
    /// 当前生效的上次累计值（字段级差分基线）
    private var lastTotal: (input: Int, cached: Int, output: Int)?
    /// 本文件 `session_meta` 的时间（fork 重放判据；取第一条）
    private var sessionStartMs: Int64?
    /// 当前生效的模型（`turn_context.payload.model` 优先）
    private var model = ""
    /// 当前生效的 cwd
    private var cwd = ""

    public private(set) var malformedLineCount = 0
    public private(set) var ignoredLineCount = 0
    public private(set) var skippedLineCount = 0

    public init() {}

    /// 纯函数入口：整段文本 → 统一事件 + 计数（无需真实 CLI 安装，fixture 直接驱动）
    public static func parse(text: String) -> TokenSourceParseReport {
        TokenSourceParseRunner.run(text: text, through: CodexRolloutParser())
    }

    public func reset() {
        sessionKey = ""
        lastTotal = nil
        sessionStartMs = nil
        model = ""
        cwd = ""
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
        switch TokenSourceJSON.string(root["type"]) {
        case "session_meta":
            return applySessionMeta(root)
        case "turn_context":
            return applyTurnContext(root)
        case "event_msg":
            return parseEventMessage(root)
        default:
            // 老格式行（无包封的 instructions / message）与其它无关事件都走这里
            ignoredLineCount += 1
            return .ignored
        }
    }

    // MARK: - 会话元信息

    private func applySessionMeta(_ root: [String: Any]) -> TokenSourceLineResult {
        let payload = TokenSourceJSON.object(root["payload"])
        if let id = TokenSourceJSON.string(payload?["id"]) ?? TokenSourceJSON.string(payload?["session_id"]) {
            sessionKey = id
        }
        if let path = TokenSourceJSON.string(payload?["cwd"]) {
            cwd = path
        }
        let tsMs = TokenSourceJSON.milliseconds(fromISO8601: root["timestamp"] as? String) ?? 0
        // 第一条 session_meta 才代表本文件起点：后面出现的（极少）不覆盖，否则 fork 判据会漂
        if sessionStartMs == nil, tsMs > 0 {
            sessionStartMs = tsMs
        }
        return .session(sessionInfo(tsMs: tsMs))
    }

    private func applyTurnContext(_ root: [String: Any]) -> TokenSourceLineResult {
        let payload = TokenSourceJSON.object(root["payload"])
        if let name = TokenSourceJSON.string(payload?["model"]) {
            model = name
        }
        if let path = TokenSourceJSON.string(payload?["cwd"]) {
            cwd = path
        }
        let tsMs = TokenSourceJSON.milliseconds(fromISO8601: root["timestamp"] as? String) ?? 0
        return .session(sessionInfo(tsMs: tsMs))
    }

    private func sessionInfo(tsMs: Int64) -> TokenSourceSessionInfo {
        TokenSourceSessionInfo(
            source: source,
            sessionKey: sessionKey,
            cwd: cwd,
            model: model.isEmpty ? Self.unknownModel : model,
            tsMs: tsMs
        )
    }

    // MARK: - 用量

    private func parseEventMessage(_ root: [String: Any]) -> TokenSourceLineResult {
        let payload = TokenSourceJSON.object(root["payload"])
        guard TokenSourceJSON.string(payload?["type"]) == "token_count" else {
            ignoredLineCount += 1
            return .ignored
        }
        // info 为 null / 缺失 → 跳过该行（不是坏行）
        guard let info = TokenSourceJSON.object(payload?["info"]) else {
            ignoredLineCount += 1
            return .ignored
        }
        guard let tsMs = TokenSourceJSON.milliseconds(fromISO8601: root["timestamp"] as? String) else {
            malformedLineCount += 1
            return .malformed("token_count 行缺少可解析的 timestamp")
        }
        // fork 重放：父会话行的时间戳早于本文件 session_meta
        if let start = sessionStartMs, tsMs < start {
            skippedLineCount += 1
            return .ignored
        }
        // 模型：turn_context 的当前值优先 → token_count.info.model（新版有）→ unknown
        let resolvedModel = model.isEmpty
            ? (TokenSourceJSON.string(info["model"]) ?? Self.unknownModel)
            : model

        if let last = TokenSourceJSON.object(info["last_token_usage"]) {
            let usage = Self.lastUsage(from: last)
            // 顺手把累计基线对齐，避免同一文件里 last 与 total 混用时重复计
            updateBaseline(from: TokenSourceJSON.object(info["total_token_usage"]))
            guard !usage.isZero else {
                skippedLineCount += 1
                return .ignored
            }
            return .usage(event(tsMs: tsMs, model: resolvedModel, usage: usage))
        }
        if let total = TokenSourceJSON.object(info["total_token_usage"]) {
            guard let usage = diffUsage(from: total) else {
                // 首行没有基线 / 累计回退：本次记 0，不算错
                skippedLineCount += 1
                return .ignored
            }
            return .usage(event(tsMs: tsMs, model: resolvedModel, usage: usage))
        }
        ignoredLineCount += 1
        return .ignored
    }

    private func event(tsMs: Int64, model: String, usage: HarnessTokenUsage) -> TokenSourceUsageEvent {
        TokenSourceUsageEvent(
            source: source,
            tsMs: tsMs,
            provider: Self.providerName,
            model: model,
            usage: usage,
            sessionKey: sessionKey,
            cwd: cwd
        )
    }

    /// 当轮用量：`cached` 是 `input` 的子集，`reasoning` 已含在 output 里
    private static func lastUsage(from object: [String: Any]) -> HarnessTokenUsage {
        let input = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["input_tokens"]) ?? 0)
        let cached = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cached_input_tokens"]) ?? 0)
        let output = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["output_tokens"]) ?? 0)
        return HarnessTokenUsage(
            uncachedInput: max(0, input - cached),
            output: output,
            cacheRead: cached,
            cacheWrite: 0,
            requestCount: 1
        )
    }

    /// 把累计值对齐成新基线（last 行带了 total 时用）
    private func updateBaseline(from total: [String: Any]?) {
        guard let total,
              let input = TokenSourceJSON.int(total["input_tokens"]),
              let cached = TokenSourceJSON.int(total["cached_input_tokens"]),
              let output = TokenSourceJSON.int(total["output_tokens"]) else { return }
        lastTotal = (input: max(0, input), cached: max(0, cached), output: max(0, output))
    }

    /// 字段级差分；返回 nil 表示「本次记 0」（无基线行，或累计回退）
    private func diffUsage(from total: [String: Any]) -> HarnessTokenUsage? {
        let input = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["input_tokens"]) ?? 0)
        let cached = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["cached_input_tokens"]) ?? 0)
        let output = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["output_tokens"]) ?? 0)
        defer { lastTotal = (input: input, cached: cached, output: output) }
        guard let base = lastTotal else { return nil }
        // 累计回退：重设基线（defer 已写），本次记 0，不记负数
        guard input >= base.input, cached >= base.cached, output >= base.output else { return nil }
        let deltaInput = input - base.input
        let deltaCached = cached - base.cached
        return HarnessTokenUsage(
            uncachedInput: max(0, deltaInput - deltaCached),
            output: output - base.output,
            cacheRead: deltaCached,
            cacheWrite: 0,
            requestCount: 1
        )
    }
}
