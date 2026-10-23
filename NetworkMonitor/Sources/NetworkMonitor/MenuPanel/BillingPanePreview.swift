#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 额度页快照示意数据（仅 DEBUG）

/// 额度页示意数据 — 供快照自证使用，release 构建完全不包含本文件
///
/// 从 `BillingPaneView.swift` 拆出（原文件因 DEBUG 快照数据超 15 KiB 规范上限）。
/// 四种形态：未配置 / 查询失败 / 遗留计划 / Open Design，字段与真实 provider 返回一致。
extension BillingPaneView {

    /// 快照自证专用（仅 DEBUG）：注入示意数据，不影响真实运行
    ///
    /// - Parameters:
    ///   - configured: false 时渲染「配置凭据」态
    ///   - errorMessage: 非空时渲染错误条（保留余额与用量数据）
    ///   - legacyLimits: 注入遗留计划百分比限额（原型 D 状态）
    ///   - legacyUsage: 注入「只有请求数、无金额/token」的用量（遗留计划真实返回形态）
    ///   - openDesign: 改用 Open Design 形态（credits 限额明细、无时间序列）
    func injectPreview(configured: Bool = true, errorMessage: String? = nil,
                       legacyLimits: Bool = false, legacyUsage: Bool = false,
                       openDesign: Bool = false) {
        let provider = Self.previewProvider(openDesign: openDesign)
        let now = Date()
        // 三种形态共用一次快照构造，避免重复堆叠参数
        var balance: BillingBalance?
        var usage: BillingUsage?
        if configured {
            if openDesign {
                // Open Design：无金额维度、额度是两条 credits 窗口、服务端不分桶
                balance = Self.previewOpenDesignBalance(now: now)
                usage = Self.previewOpenDesignUsage(endingAt: now)
            } else {
                balance = Self.previewOllamaBalance(now: now, legacy: legacyLimits)
                usage = Self.previewOllamaUsage(endingAt: now, legacyOnly: legacyUsage)
            }
        }
        update(BillingMonitor.Snapshot(providers: [provider],
                                       selectedProviderID: provider.id,
                                       isConfigured: configured,
                                       balance: balance, usage: usage,
                                       range: .last24Hours, lastUpdated: now,
                                       isLoading: false, errorMessage: errorMessage))
    }

    /// 示意 provider 描述符（字段与真实注册表一致，保证页头与文案走同一路径）
    private static func previewProvider(openDesign: Bool) -> BillingMonitor.ProviderDescriptor {
        openDesign
            ? BillingMonitor.ProviderDescriptor(
                id: "open-design", displayName: "Open Design", symbolName: "paintpalette",
                credentialHint: "Open Design session token", supportsModelBreakdown: true,
                supportsTimeSeries: false, credentialPageURL: URL(string: "https://open-design.ai/"))
            : BillingMonitor.ProviderDescriptor(
                id: "ollama", displayName: "Ollama", symbolName: "cloud",
                credentialHint: "Ollama API Key", supportsModelBreakdown: true,
                credentialPageURL: URL(string: "https://ollama.com/settings/keys"))
    }

    /// Ollama 示意余额：正常态带内含额度，遗留态只有已购余额 + 百分比限额
    private static func previewOllamaBalance(now: Date, legacy: Bool) -> BillingBalance {
        guard !legacy else {
            return BillingBalance(purchasedUSD: 25, percentLimits: [
                BillingPercentLimit(id: "session", title: "会话", remainingFraction: 0.75,
                                    resetsAt: now.addingTimeInterval(-3_600)),
                BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 0.40,
                                    resetsAt: now.addingTimeInterval(3 * 86_400))])
        }
        let period = BillingPeriod(start: now.addingTimeInterval(-12 * 86_400),
                                   end: now.addingTimeInterval(18 * 86_400))
        return BillingBalance(included: BillingIncludedBalance(remainingUSD: 72.50,
                                                              allowanceUSD: 100, period: period),
                              purchasedUSD: 25)
    }

    /// Open Design 示意余额：5 小时与每周两个 credits 窗口（字段与真实接口一致）
    private static func previewOpenDesignBalance(now: Date) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "session", title: "5 小时",
                                remainingFraction: 1 - 157 / 50_000,
                                resetsAt: now.addingTimeInterval(2 * 3_600),
                                usedAmount: 157, limitAmount: 50_000, unitLabel: "credits"),
            BillingPercentLimit(id: "weekly", title: "每周",
                                remainingFraction: 1 - 76_412 / 150_000,
                                resetsAt: now.addingTimeInterval(4 * 86_400),
                                usedAmount: 76_412, limitAmount: 150_000, unitLabel: "credits")])
    }

    /// Open Design 示意用量：有指标与按模型 token，但没有分桶（服务端不分桶）
    private static func previewOpenDesignUsage(endingAt now: Date) -> BillingUsage {
        BillingUsage(range: .last24Hours, granularity: .hour,
                     start: now.addingTimeInterval(-24 * 3_600), end: now,
                     totals: BillingMetrics(requestCount: 1_284, inputTokens: 168_400_000,
                                            cachedInputTokens: 42_000_000, outputTokens: 5_600_000),
                     buckets: [],
                     groups: [Self.previewModel("claude-sonnet-4-5", 912, 121_000_000, 30_000_000,
                                                3_900_000),
                              Self.previewModel("gpt-5-codex", 372, 47_400_000, 12_000_000,
                                                1_700_000)])
    }

    /// Ollama 24 小时示意用量：25 个小时桶（稀疏写法只列非零桶）+ 2 个模型
    ///
    /// - Parameter legacyOnly: 遗留计划真实返回只有 request_count（无金额 / token / 模型分组）
    private static func previewOllamaUsage(endingAt now: Date, legacyOnly: Bool) -> BillingUsage {
        let calendar = Calendar.current
        let end = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour],
                                                             from: now)) ?? now
        let start = end.addingTimeInterval(-24 * 3_600)
        // 非零桶：遗留态按请求数、正常态按金额（其余小时为 0）
        let counts = [4: 120, 10: 860, 21: 2_400, 22: 6_300, 23: 8_200, 24: 3_400]
        let amounts: [Int: Double] = [10: 0.0052, 22: 0.0088, 23: 0.0042, 24: 0.0032]
        let buckets = (0..<25).map { index -> BillingBucket in
            let begin = start.addingTimeInterval(Double(index) * 3_600)
            let usd = legacyOnly ? nil : amounts[index]
            let requests = legacyOnly ? (counts[index] ?? 0) : (usd == nil ? 0 : 1)
            return BillingBucket(start: begin, end: begin.addingTimeInterval(3_600),
                                 isPartial: index == 24,
                                 metrics: BillingMetrics(requestCount: requests, usageUSD: usd))
        }
        let totals = legacyOnly
            ? BillingMetrics(requestCount: 26_118)
            : BillingMetrics(requestCount: 15, usageUSD: 0.01718, inputTokens: 106_000,
                             cachedInputTokens: 46_000, outputTokens: 13_600)
        let groups = legacyOnly
            ? []
            : [Self.previewModel("glm-5.3-flash", 12, usd: 0.0132),
               Self.previewModel("gpt-oss:120b", 3, usd: 0.0040)]
        return BillingUsage(range: .last24Hours, granularity: .hour, start: start,
                            end: end.addingTimeInterval(3_600), totals: totals,
                            buckets: buckets, groups: groups)
    }

    /// 模型分组简写（请求数 / token 三项 / 可选金额）
    private static func previewModel(_ name: String, _ requests: Int, _ input: Int = 0,
                                     _ cached: Int = 0, _ output: Int = 0,
                                     usd: Double? = nil) -> BillingGroup {
        BillingGroup(name: name, metrics: BillingMetrics(requestCount: requests, usageUSD: usd,
                                                         inputTokens: input,
                                                         cachedInputTokens: cached,
                                                         outputTokens: output))
    }
}
#endif
