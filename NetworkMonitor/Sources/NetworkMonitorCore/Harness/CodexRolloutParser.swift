import Foundation

// MARK: - Codex CLI rollout 行解析

/// Codex CLI rollout（`$CODEX_HOME/sessions/.../rollout-*.jsonl`）行解析器
///
/// 口径要点（上游 `codex-rs` 源码为准，逐条见函数注释）：
/// - **用量优先 `token_usage_record`**（每个完成的响应一行，`payload.usage` 是该响应的精确用量，
///   上游注明「not accumulated, estimated, or replayed」）；`event_msg/token_count` 降级为兜底。
///   两者在同一文件里并存时**按响应去重、绝不相加**——同一响应两条都记就是双算；
/// - **`cached_input_tokens` 是 `input_tokens` 的子集** → `uncachedInput = input - cached`；
///   `cache_write_input_tokens` → `cacheWrite`（老格式无该字段时缺省 0）；
/// - **`reasoning_output_tokens` 已含在 `output_tokens` 里**，不再相加；
/// - `last_token_usage` 优先；只有 `total_token_usage` 时按字段差分；
/// - **累计回退**（compaction / fork / 陈旧快照）重设基线、本次记 0，绝不记负数；
/// - fork 会话会在文件头重放父会话的用量行（时间戳早于本文件 `session_meta`）→ 跳过；
/// - 老格式（2025-09-06 之前）没有行包封、没有 `token_count` → 全部 ignored，
///   归为「该文件无用量」而不是错误。
///
/// 一个实例对应一个文件，换文件前调 `reset()`。
public final class CodexRolloutParser: TokenLineParsing, @unchecked Sendable {
    /// Codex CLI 跑 OpenAI 系模型，rollout 里不带 provider 字段，故按来源常量给
    public static let providerName = "openai"
    /// 模型缺失时的兜底
    public static let unknownModel = "unknown"

    /// rollout 行的 `type` 白名单（上游 `history/src/rollout_payload.rs` 的 13 个变体，
    /// `#[serde(tag = "type", rename_all = "snake_case")]`）
    ///
    /// 列出来只为「认得出」：与用量无关的 9 种忽略、**未知类型同样忽略且不计 malformed**
    /// ——上游会持续新增变体，把未知当坏行只会污染诊断计数。
    public static let knownRolloutTypes: Set<String> = [
        "session_meta", "dynamic_tools_updated", "response_item",
        "inter_agent_communication", "inter_agent_communication_metadata", "compacted",
        "turn_context", "token_usage_record", "world_state", "retained_context",
        "security_risk_score", "event_msg", "realtime_item",
    ]

    public let source: TokenSourceID = .codex

    /// 当前生效的会话键（`session_meta.payload.id`，缺失时用 `token_usage_record.thread_id`）
    private var sessionKey = ""
    /// 当前生效的上次累计值（字段级差分基线）
    private var lastTotal: (input: Int, cached: Int, cacheWrite: Int, output: Int)?
    /// 本文件 `session_meta` 的时间（fork 重放判据；取第一条）
    private var sessionStartMs: Int64?
    /// 当前生效的模型（`turn_context.payload.model` 优先）
    private var model = ""
    /// 当前生效的 cwd
    private var cwd = ""
    /// 已计入的响应键（`response_id`）——resume / fork 会重放同一响应
    private var seenResponses = Set<String>()
    /// 本文件出现过 `token_usage_record`：此后 `token_count` 只可能是同一响应的重复
    private var authoritativeUsageSeen = false

    public private(set) var malformedLineCount = 0
    public private(set) var ignoredLineCount = 0
    public private(set) var skippedLineCount = 0
    /// 白名单外的行类型数（诊断用：上游新增变体时可见，不影响统计）
    public private(set) var unknownTypeLineCount = 0

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
        seenResponses = []
        authoritativeUsageSeen = false
        malformedLineCount = 0
        ignoredLineCount = 0
        skippedLineCount = 0
        unknownTypeLineCount = 0
    }

    public func parse(line: Data) -> TokenSourceLineResult {
        guard !TokenSourceJSON.isBlank(line) else { return .ignored }
        guard let root = TokenSourceJSON.object(from: line) else {
            malformedLineCount += 1
            return .malformed("非 JSON 对象")
        }
        guard let type = TokenSourceJSON.string(root["type"]) else {
            // 老格式行（无包封的 instructions / message）与统计无关
            ignoredLineCount += 1
            return .ignored
        }
        switch type {
        case "session_meta": return applySessionMeta(root)
        case "turn_context": return applyTurnContext(root)
        case "token_usage_record": return applyTokenUsageRecord(root)
        case "event_msg": return parseEventMessage(root)
        default:
            if !Self.knownRolloutTypes.contains(type) { unknownTypeLineCount += 1 }
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

    // MARK: - 权威用量（token_usage_record）

    /// 一个响应完成时的精确用量
    ///
    /// 上游 `TokenUsageRecord` 带三份用量：`usage`（该响应）/
    /// `turn_token_usage`（本 turn 累计）/ `thread_token_usage`（本线程累计）。
    /// **只取 `usage`**：把三份相加等于立刻虚高数倍；累计值只作去重键与对账。
    private func applyTokenUsageRecord(_ root: [String: Any]) -> TokenSourceLineResult {
        let payload = TokenSourceJSON.object(root["payload"])
        // 会话键兜底：session_meta 缺失（截断文件）时 `thread_id` 与它就是同一个 id
        if sessionKey.isEmpty {
            sessionKey = TokenSourceJSON.string(payload?["thread_id"])
                ?? TokenSourceJSON.string(payload?["session_id"]) ?? ""
        }
        guard let usageObject = TokenSourceJSON.object(payload?["usage"]) else {
            // 字段缺失 → 跳过该行，不判坏行
            skippedLineCount += 1
            return .ignored
        }
        guard let tsMs = TokenSourceJSON.milliseconds(fromISO8601: root["timestamp"] as? String) else {
            malformedLineCount += 1
            return .malformed("token_usage_record 行缺少可解析的 timestamp")
        }
        // fork 重放：父会话的用量行时间戳早于本文件 session_meta
        if let start = sessionStartMs, tsMs < start {
            skippedLineCount += 1
            return .ignored
        }
        let usage = Self.usage(from: usageObject)
        // 四桶全零的记录没有信息量：跳过并计数，不让它虚增请求数
        guard usage.totalTokens > 0 else {
            skippedLineCount += 1
            return .ignored
        }
        // 同一响应可能被 resume / fork 重放：按 response_id 去重
        if let key = Self.responseKey(payload: payload), !seenResponses.insert(key).inserted {
            skippedLineCount += 1
            return .ignored
        }
        // 本文件已是权威格式：token_count 描述的是同一批响应，继续记就是双算
        authoritativeUsageSeen = true
        return .usage(event(tsMs: tsMs, model: model.isEmpty ? Self.unknownModel : model, usage: usage))
    }


    // MARK: - 兜底用量（event_msg / token_count）

    private func parseEventMessage(_ root: [String: Any]) -> TokenSourceLineResult {
        let payload = TokenSourceJSON.object(root["payload"])
        guard TokenSourceJSON.string(payload?["type"]) == "token_count" else {
            ignoredLineCount += 1
            return .ignored
        }
        // 兜底口径：本文件已有权威记录时，token_count 是同一响应的另一条写法。
        // 上游的写入顺序是「先 token_usage_record，后 TokenCount 事件」，
        // 故只要见过记录，后面每个 token_count 都已计入 → 跳过（去重而非相加）。
        guard !authoritativeUsageSeen else {
            skippedLineCount += 1
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
            let usage = Self.usage(from: last)
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

    // MARK: - 累计基线（token_count 差分）


    /// 把累计值对齐成新基线（last 行带了 total 时用）
    private func updateBaseline(from total: [String: Any]?) {
        guard let total,
              let input = TokenSourceJSON.int(total["input_tokens"]),
              let cached = TokenSourceJSON.int(total["cached_input_tokens"]),
              let output = TokenSourceJSON.int(total["output_tokens"]) else { return }
        lastTotal = (input: max(0, input), cached: max(0, cached),
                     cacheWrite: max(0, TokenSourceJSON.int(total["cache_write_input_tokens"]) ?? 0),
                     output: max(0, output))
    }

    /// 字段级差分；返回 nil 表示「本次记 0」（无基线行，或累计回退）
    private func diffUsage(from total: [String: Any]) -> HarnessTokenUsage? {
        let input = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["input_tokens"]) ?? 0)
        let cached = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["cached_input_tokens"]) ?? 0)
        let cacheWrite = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["cache_write_input_tokens"]) ?? 0)
        let output = TokenSourceJSON.nonNegative(TokenSourceJSON.int(total["output_tokens"]) ?? 0)
        defer { lastTotal = (input: input, cached: cached, cacheWrite: cacheWrite, output: output) }
        guard let base = lastTotal else { return nil }
        // 累计回退：重设基线（defer 已写），本次记 0，不记负数
        guard input >= base.input, cached >= base.cached,
              cacheWrite >= base.cacheWrite, output >= base.output else { return nil }
        let deltaInput = input - base.input
        let deltaCached = cached - base.cached
        return HarnessTokenUsage(
            uncachedInput: max(0, deltaInput - deltaCached),
            output: output - base.output,
            cacheRead: deltaCached,
            cacheWrite: cacheWrite - base.cacheWrite,
            requestCount: 1
        )
    }
}
