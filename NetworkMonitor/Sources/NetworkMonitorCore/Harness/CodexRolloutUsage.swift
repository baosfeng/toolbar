import Foundation

// MARK: - Codex rollout 用量换算（纯函数）

/// 四桶换算与响应去重键 —— 从 `CodexRolloutParser` 拆出，让主文件留在单文件上限内
extension CodexRolloutParser {

    /// 用量对象 → 四桶
    ///
    /// - `cached_input_tokens` 是 `input_tokens` 的**子集** → 未缓存 = 差；
    /// - `cache_write_input_tokens`（`protocol.rs` 的 `TokenUsage` 字段，老格式没有该键）单列；
    /// - `reasoning_output_tokens` 已含在 `output_tokens` 里，不再相加。
    static func usage(from object: [String: Any]) -> HarnessTokenUsage {
        let input = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["input_tokens"]) ?? 0)
        let cached = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cached_input_tokens"]) ?? 0)
        let cacheWrite = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cache_write_input_tokens"]) ?? 0)
        let output = TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["output_tokens"]) ?? 0)
        return HarnessTokenUsage(
            uncachedInput: max(0, input - cached),
            output: output,
            cacheRead: cached,
            cacheWrite: cacheWrite,
            requestCount: 1
        )
    }

    /// 去重键：优先 `response_id`；缺失时用线程累计值指纹（每次响应必然推进，故同一响应同值）
    static func responseKey(payload: [String: Any]?) -> String? {
        if let id = TokenSourceJSON.string(payload?["response_id"]) { return "r:" + id }
        if let thread = TokenSourceJSON.object(payload?["thread_token_usage"]) {
            return "t:" + fingerprint(thread)
        }
        return nil
    }

    /// 用量对象的字段指纹（用于跨行核对同一响应）
    static func fingerprint(_ object: [String: Any]) -> String {
        ["input_tokens", "cached_input_tokens", "cache_write_input_tokens",
         "output_tokens", "reasoning_output_tokens", "total_tokens"]
            .map { String(TokenSourceJSON.int(object[$0]) ?? 0) }
            .joined(separator: "/")
    }
}
