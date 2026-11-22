import Foundation

// MARK: - OpenCode 消息 JSON 的用量 / 模型形状（v1 与 v2 两代）

/// OpenCode `message.data` / `session_message.data` 里与用量相关的字段形状
///
/// 上游两代形状（`anomalyco/opencode`，见 `packages/schema/src/session-message.ts` 与 `token-usage.ts`）：
/// - **v1**：顶层 `providerID` / `modelID`，`tokens{total?, input, output, reasoning, cache{read, write}}`；
/// - **v2**：`model{providerID, id, variant}`（`model.ts` 的 `Model.Ref`），
///   `tokens{input, output, reasoning, cache{read, write}}` —— **没有 total**。
///
/// 取字段一律「先新后旧」：不按表名分支，同一份代码对两代形状都能取到。
public enum OpenCodeUsageShape {

    /// 模型标识：嵌套 `model{providerID, id}`（v2）优先，回落顶层 `providerID` / `modelID`（v1）
    ///
    /// `variant` 刻意不拼进模型名：它是同一模型的不同参数档，排行与占比按模型族聚合更有意义；
    /// 需要区分档位时再单独取。
    public static func model(from root: [String: Any],
                             unknownProvider: String,
                             unknownModel: String) -> (provider: String, model: String) {
        let nested = TokenSourceJSON.object(root["model"])
        let provider = TokenSourceJSON.string(nested?["providerID"])
            ?? TokenSourceJSON.string(root["providerID"])
            ?? unknownProvider
        let model = TokenSourceJSON.string(nested?["id"])
            ?? TokenSourceJSON.string(root["modelID"])
            ?? unknownModel
        return (provider, model)
    }

    /// 四桶映射：`input` 不含缓存；`output` 加上单列的 `reasoning`
    ///
    /// `total` 是**派生值、不是权威总量**：五桶能拆就完全忽略它。只有五桶全零、`total` 非零的
    /// legacy 行（拆不出缓存归属）才把它整笔记到 `uncachedInput`——保住请求数与体量，
    /// 不去猜缓存命中（猜错会污染缓存命中率）。
    public static func usage(from tokens: [String: Any]) -> HarnessTokenUsage {
        let cache = TokenSourceJSON.object(tokens["cache"])
        let input = value(tokens, "input")
        let output = value(tokens, "output")
        let reasoning = value(tokens, "reasoning")
        let cacheRead = value(cache, "read")
        let cacheWrite = value(cache, "write")
        let split = input + output + reasoning + cacheRead + cacheWrite
        guard split > 0 else {
            return HarnessTokenUsage(uncachedInput: value(tokens, "total"), requestCount: 1)
        }
        return HarnessTokenUsage(
            uncachedInput: input,
            output: output + reasoning,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            requestCount: 1
        )
    }

    /// 宽松取非负整数（缺失 / 类型不符 / 负数一律 0）
    private static func value(_ object: [String: Any]?, _ key: String) -> Int {
        guard let object else { return 0 }
        return TokenSourceJSON.nonNegative(TokenSourceJSON.int(object[key]) ?? 0)
    }
}
