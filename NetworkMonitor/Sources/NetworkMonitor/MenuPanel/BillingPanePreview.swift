#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureBilling

// MARK: - 额度页快照示意数据（仅 DEBUG）

/// 额度页示意数据 —— 供快照自证使用，release 构建完全不包含本文件
///
/// 数据与原型 F1 一致：6 家（3 用量型 + 3 余额型），用量型两家两窗口、一家两窗口且已用尽，
/// 余额型覆盖「正常金额 / 另一种币种 / 无限制」三种形态，图表带 7 天与 30 天的真实分桶。
extension BillingPaneView {

    /// 快照自证专用（仅 DEBUG）：注入示意数据，不影响真实运行
    ///
    /// - Parameters:
    ///   - configured: 预留位（数据层已过滤未配置 provider，这里恒为可见）
    ///   - errorMessage: 非空时第一家渲染错误态（保留上次成功数据 + 错误条）
    ///   - legacyUsage: 注入「只有请求数、无金额 / token」的用量（遗留计划真实返回形态）
    ///   - openDesign: 追加 Open Design 两家（同名不同实例）
    ///   - opencodeGo: 追加 OpenCode Go（三窗口，验证三列布局）
    ///   - empty: 0 个可见 provider → 空态
    ///   - singleProvider: 只留第一家（单 provider 密度）
    func injectPreview(configured: Bool = true, errorMessage: String? = nil,
                       legacyUsage: Bool = false, openDesign: Bool = false,
                       opencodeGo: Bool = false, empty: Bool = false,
                       singleProvider: Bool = false) {
        let now = SnapshotClock.now
        if empty {
            update(BillingMonitor.Snapshot(states: []))
            return
        }
        var states: [BillingMonitor.ProviderState] = [
            Self.previewState(id: "ollama", name: "Ollama", symbol: "cloud",
                              balance: Self.previewOllamaBalance(now: now),
                              usage: Self.previewUsage(endingAt: now, legacyOnly: legacyUsage,
                                                       requests: [412, 508, 623, 470, 561, 644, 539]),
                              error: errorMessage, now: now),
        ]
        if openDesign && !singleProvider {
            states.append(Self.previewState(id: "open-design", name: "Open Design", symbol: "paintpalette",
                                            balance: Self.previewOpenDesignBalance(now: now),
                                            usage: Self.previewUsage(endingAt: now, legacyOnly: false,
                                                                     requests: [380, 470, 590, 640, 720, 800, 690]),
                                            error: nil, now: now))
            // 同名不同实例：展示名带 (home)，验证「一行一家」不会把两个实例看成重复
            states.append(Self.previewState(id: "open-design::home", name: "Open Design",
                                            symbol: "paintpalette",
                                            balance: Self.previewFullBalance(now: now),
                                            usage: Self.previewUsage(endingAt: now, legacyOnly: false,
                                                                     requests: [120, 140, 90, 60, 20, 4, 0]),
                                            error: nil, now: now, instanceLabel: "home"))
        }
        if opencodeGo && !singleProvider {
            states.append(Self.previewState(id: "opencode-go", name: "OpenCode Go", symbol: "terminal",
                                            balance: Self.previewOpencodeGoBalance(now: now),
                                            usage: nil, error: nil, now: now))
        }
        if !singleProvider {
            // 余额型三家：金额 / 另一币种 / 无限制
            states.append(Self.previewBalanceState(id: "deepseek", name: "DeepSeek",
                                                   symbol: "sparkles", amount: 36.74,
                                                   currency: "CNY", now: now))
            states.append(Self.previewBalanceState(id: "moonshot", name: "Moonshot",
                                                   symbol: "moon", amount: 88.50,
                                                   currency: "CNY", now: now))
            states.append(Self.previewBalanceState(id: "openrouter", name: "OpenRouter",
                                                   symbol: "arrow.triangle.branch",
                                                   amount: nil, currency: "USD", now: now))
        }
        update(BillingMonitor.Snapshot(states: states))
        // 首屏默认在主表（二级页由 captureCreditsExpanded 单独取景）
        expandForPreview(nil)
        logRowHeights()
    }

    /// 行高台账（DEBUG）：验收要看「四行等高」，靠肉眼估不准
    ///
    /// 写进快照目录的 credits-row-heights.txt（GUI 进程的 stdout 抓不到，
    /// 而 info 日志有字符预算），内容形如：ollama=34.0 open-design=34.0 …
    private func logRowHeights() {
        let heights = tableView.snapshotRowHeights()
        let text = heights.map { $0.id + "=" + String(format: "%.1f", $0.height) }
            .joined(separator: " ")
        guard let directory = ProcessInfo.processInfo.environment["NM_SNAPSHOT_DIR"],
              !directory.isEmpty else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("credits-row-heights.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 状态构造

    private static func previewState(id: String, name: String, symbol: String,
                                     balance: BillingBalance?, usage: BillingUsage?,
                                     error: String?, now: Date,
                                     instanceLabel: String? = nil) -> BillingMonitor.ProviderState {
        BillingMonitor.ProviderState(
            descriptor: BillingMonitor.ProviderDescriptor(
                id: id, instanceLabel: instanceLabel,
                displayName: instanceLabel.map { name + " (" + $0 + ")" } ?? name,
                symbolName: symbol,
                credentialHint: name + " API Key", supportsModelBreakdown: true),
            range: .last7Days,
            isConfigured: true,
            balance: balance,
            usage: usage,
            lastUpdated: now,
            isLoading: false,
            errorMessage: error)
    }

    private static func previewBalanceState(id: String, name: String, symbol: String,
                                            amount: Double?, currency: String,
                                            now: Date) -> BillingMonitor.ProviderState {
        BillingMonitor.ProviderState(
            descriptor: BillingMonitor.ProviderDescriptor(
                id: id, displayName: name, symbolName: symbol,
                credentialHint: name + " API Key", supportsModelBreakdown: false,
                supportsUsage: false, supportsTimeSeries: false),
            range: .last7Days,
            isConfigured: true,
            balance: BillingBalance(purchasedUSD: amount, currencyCode: currency),
            usage: nil,
            lastUpdated: now,
            isLoading: false,
            errorMessage: nil)
    }

    // MARK: - 余额

    /// Ollama 两项窗口：会话 68% / 每周 4%（限流）
    private static func previewOllamaBalance(now: Date) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "session", title: "会话", remainingFraction: 0.6795,
                                resetsAt: now.addingTimeInterval(3_600)),
            BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 0.0421,
                                resetsAt: now.addingTimeInterval(2 * 86_400), badge: "已限流"),
        ])
    }

    /// Open Design 两项窗口：5 小时 63% / 每周 27%
    private static func previewOpenDesignBalance(now: Date) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "session", title: "5 小时", remainingFraction: 0.6326,
                                resetsAt: now.addingTimeInterval(2 * 3_600),
                                usedAmount: 18_370, limitAmount: 50_000, unitLabel: "credits"),
            BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 0.2739,
                                resetsAt: now.addingTimeInterval(4 * 86_400),
                                usedAmount: 108_915, limitAmount: 150_000, unitLabel: "credits"),
        ])
    }

    /// 满额实例（原型里 Open Design (home) 两窗口都是 100%）
    ///
    /// 危险档配色由 Ollama 每周 4.21% / OpenCode Go 每月 0% 覆盖，这里不必再造一个全零样本；
    /// 全零态若出现在真实数据里，判据（BillingCellLayout.level）与配色都已单测守住。
    private static func previewFullBalance(now: Date) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "session", title: "5 小时", remainingFraction: 1,
                                resetsAt: now.addingTimeInterval(2 * 3_600)),
            BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 1,
                                resetsAt: now.addingTimeInterval(6 * 86_400)),
        ])
    }

    /// OpenCode Go 三窗口（验证三列布局；每月窗口已用尽）
    private static func previewOpencodeGoBalance(now: Date) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "window:rolling", title: "5 小时", remainingFraction: 0.62,
                                resetsAt: now.addingTimeInterval(2 * 3_600)),
            BillingPercentLimit(id: "window:weekly", title: "每周", remainingFraction: 0.48,
                                resetsAt: now.addingTimeInterval(4 * 86_400)),
            BillingPercentLimit(id: "window:monthly", title: "每月", remainingFraction: 0,
                                resetsAt: now.addingTimeInterval(18 * 86_400), badge: "已限流"),
        ])
    }

    // MARK: - 用量

    /// 7 天用量（含 24h / 30d 三个范围，页级分段切档时图表立即有数据）
    ///
    /// - Parameter requests: 7 天每天的请求数（顺序 = 最早到今天）
    private static func previewUsage(endingAt now: Date, legacyOnly: Bool,
                                     requests: [Int]) -> BillingUsage {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(requests.count - 1), to: today) ?? today
        let dayBuckets = requests.enumerated().map { index, count -> BillingBucket in
            let begin = calendar.date(byAdding: .day, value: index, to: start) ?? start
            return BillingBucket(start: begin,
                                 end: calendar.date(byAdding: .day, value: 1, to: begin) ?? begin,
                                 isPartial: index == requests.count - 1,
                                 metrics: BillingMetrics(requestCount: legacyOnly ? count : max(count / 7, 1),
                                                         usageUSD: legacyOnly ? nil : Double(count) / 90_000))
        }
        let total = requests.reduce(0, +)
        let groups: [BillingGroup] = legacyOnly ? [] : [
            BillingGroup(name: "deepseek-chat",
                         metrics: BillingMetrics(requestCount: total * 4 / 10,
                                                 usageUSD: 0.42, inputTokens: 12_040_000, outputTokens: 1_200_000)),
            BillingGroup(name: "kimi-k2",
                         metrics: BillingMetrics(requestCount: total * 26 / 100,
                                                 usageUSD: 0.26, inputTokens: 8_060_000, outputTokens: 900_000)),
            BillingGroup(name: "glm-5",
                         metrics: BillingMetrics(requestCount: total * 18 / 100,
                                                 usageUSD: 0.18, inputTokens: 5_120_000, outputTokens: 600_000)),
            BillingGroup(name: "qwen3-coder",
                         metrics: BillingMetrics(requestCount: total * 9 / 100,
                                                 usageUSD: 0.09, inputTokens: 2_600_000, outputTokens: 300_000)),
            BillingGroup(name: "其他模型",
                         metrics: BillingMetrics(requestCount: total * 7 / 100,
                                                 usageUSD: 0.07, inputTokens: 1_970_000, outputTokens: 200_000)),
        ]
        let week = BillingUsage(range: .last7Days, granularity: .day, start: start,
                            end: now, totals: BillingMetrics(requestCount: total,
                                                             usageUSD: legacyOnly ? nil : 1.02, inputTokens: 30_000_000,
                                                             cachedInputTokens: 8_000_000, outputTokens: 3_200_000),
                            buckets: dayBuckets, groups: groups)
        return week
    }
}
#endif
