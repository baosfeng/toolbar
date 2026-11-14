import Foundation
import NetworkMonitorCore

// MARK: - Open Design 用量窗口与能力测试

/// 用量解码、查询窗口边界、窗口命名与 provider 能力声明 — 从 `OpenDesignBillingTests` 拆出
/// （单文件超 15 KiB 上限，按「入口 + 主题」拆分）。
func runOpenDesignUsageTests() {
    print("\n🧪 Testing OpenDesign usage decoding...")
    testOpenDesignUsageDecoding()

    print("\n🧪 Testing OpenDesign query window...")
    testOpenDesignQueryWindow()

    print("\n🧪 Testing OpenDesign window title...")
    testOpenDesignWindowTitle()

    print("\n🧪 Testing OpenDesign provider capabilities...")
    testOpenDesignProviderCapabilities()

    print("✅ Open Design 用量窗口与能力 works")
}

// MARK: - 用量解码

private func testOpenDesignUsageDecoding() {
    // 顶层聚合是全范围汇总，取 summary + totalCount，不碰 entries
    let json = """
    { "workspaceId": "fbpzndory1pwn0jgb6r68ed8",
      "entries": [ { "id": "workspace-usage:x", "inputTokens": 53548, "outputTokens": 1358 } ],
      "summary": { "inputTokens": 2129138478, "outputTokens": 12300418,
                   "cacheReadTokens": 2112637440, "cacheWriteTokens": 0 },
      "filterOptions": { "initiators": ["清风"], "runtimes": ["deepseek-v4.1-flash"] },
      "totalCount": 16206, "hasMore": true }
    """
    let window = DateInterval(start: Date(timeIntervalSince1970: 0),
                             end: Date(timeIntervalSince1970: 86_400))
    guard let decoded = try? OpenDesignBillingProvider.decodeUsageSummary(from: Data(json.utf8),
                                                                         requestedRange: .last7Days,
                                                                         window: window) else {
        assertEqual("decode failed", "", "用量解码不应失败")
        return
    }
    assertEqual(decoded.totals.requestCount, 16_206, "请求数取全范围 totalCount")
    assertEqual(decoded.totals.inputTokens ?? -1, 2_129_138_478, "输入 token 取 summary")
    assertEqual(decoded.totals.cachedInputTokens ?? -1, 2_112_637_440, "缓存 token 取 cacheReadTokens")
    assertEqual(decoded.totals.outputTokens ?? -1, 12_300_418, "输出 token")
    assertEqual(decoded.totals.usageUSD == nil, true, "不展示金额（编码计划无真实扣费）")
    assertEqual(decoded.runtimes, ["deepseek-v4.1-flash"], "模型列表来自 filterOptions")

    // 空用量：全 0，模型列表缺失
    let empty = """
    { "workspaceId": "w", "entries": [],
      "summary": { "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0 } }
    """
    let emptyTotals = try? OpenDesignBillingProvider.decodeUsageTotals(from: Data(empty.utf8))
    assertEqual(emptyTotals?.requestCount ?? -1, 0, "缺 totalCount 按 0")
    assertEqual(emptyTotals?.inputTokens ?? -1, 0, "空用量输入 0")

    // 缺 summary：invalidResponse
    var missingError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeUsageTotals(from: Data(#"{ "entries": [] }"#.utf8))
    } catch let error as BillingError {
        missingError = error
    } catch {}
    if case .invalidResponse = missingError {} else {
        assertEqual("\(String(describing: missingError))", "invalidResponse", "缺 summary 抛 invalidResponse")
    }

    // token 展示形态：跟随设置页「数值单位」，默认自动档 → B
    assertEqual(formatTokenCount(2_112_637_440), "2.11B", "缓存 token 缩写（自动档）")
    // 切到中文档 → 亿（同一数值换单位写法，UI 不需要改代码）
    let originalStorage = AppContext.shared.storage
    let isolatedStorage = InMemoryStorage()
    AppContext.shared.configure(storage: isolatedStorage)
    defer { AppContext.shared.configure(storage: originalStorage) }
    NumberUnitPreferences(storage: isolatedStorage).setStyle(.chinese)
    assertEqual(formatTokenCount(2_112_637_440), "21.13亿", "缓存 token 缩写（中文档，2 位四舍五入）")
}

// MARK: - 查询窗口

private func testOpenDesignQueryWindow() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    // 2026-10-23 23:30 本地时间
    let now = Date(timeIntervalSince1970: 1_792_769_400)
    let components = calendar.dateComponents(in: calendar.timeZone, from: now)
    assertEqual(components.day, 23, "基准日期为 23 日")

    // 24 小时：整点对齐、跨 24 个桶
    let day = BillingRange.last24Hours.queryWindow(now: now, calendar: calendar)
    let dayComponents = calendar.dateComponents([.hour, .minute], from: day.start)
    assertEqual(dayComponents.minute, 0, "起点按整点对齐")
    assertEqual(Int(day.duration / 3_600), 23, "24 小时范围含 23 个整点到当前")

    // 7 天：起点取 6 天前的自然日；终点截到当前时刻（明天 0 点属未来，服务端 400）
    let week = BillingRange.last7Days.queryWindow(now: now, calendar: calendar)
    let weekStart = calendar.dateComponents([.year, .month, .day, .hour], from: week.start)
    assertEqual(weekStart.day, 17, "7 天窗口起点为 17 日")
    assertEqual(weekStart.hour, 0, "7 天窗口起点为 0 点")
    assertEqual(week.end.timeIntervalSince(now), 0, "7 天窗口终点截到当前时刻")
    assertEqual(week.duration <= 7 * 86_400, true, "7 天窗口跨度不超服务端上限")

    // 30 天：起点裁到 7 天前上限（服务端只认最近 7 天，超窗整段 400）
    let month = BillingRange.last30Days.queryWindow(now: now, calendar: calendar)
    assertEqual(month.start.timeIntervalSince(now), -7 * 86_400, "30 天窗口起点裁到 7 天前")
    assertEqual(month.duration <= 7 * 86_400, true, "30 天窗口跨度不超服务端上限")

    // 粒度映射
    assertEqual(BillingRange.last24Hours.granularity, .hour, "24h 按小时")
    assertEqual(BillingRange.last7Days.granularity, .day, "7d 按天")
    assertEqual(BillingRange.last30Days.granularity, .day, "30d 按天")
}

// MARK: - 窗口命名

private func testOpenDesignWindowTitle() {
    assertEqual(OpenDesignBillingProvider.windowTitle(durationSeconds: 18_000), "5 小时",
                "5 小时窗口")
    assertEqual(OpenDesignBillingProvider.windowTitle(durationSeconds: 604_800), "每周",
                "每周窗口")
    assertEqual(OpenDesignBillingProvider.windowTitle(durationSeconds: 86_400), "1 天",
                "整日窗口")
    assertEqual(OpenDesignBillingProvider.windowTitle(durationSeconds: 3_600), "1 小时",
                "1 小时窗口")
    assertEqual(OpenDesignBillingProvider.windowTitle(durationSeconds: nil), "编码计划",
                "缺时长兜底")
    assertEqual(OpenDesignBillingProvider.windowTitle(durationSeconds: 0), "编码计划",
                "零时长兜底")
}

// MARK: - provider 能力声明

/// 校验两家 provider 的凭据页地址与时间序列能力（UI 分支依赖这两个声明）
func testOpenDesignProviderCapabilities() {
    let minimal = MinimalBillingProvider(id: "minimal")
    assertEqual(minimal.supportsTimeSeries, true, "默认支持时间序列")
    assertEqual(minimal.credentialPageURL == nil, true, "默认无凭据页")
    assertEqual(minimal.environmentCredentialKey, "BILLING_MINIMAL_API_KEY", "默认环境变量键名")

    let ollama = OllamaBillingProvider()
    assertEqual(ollama.credentialPageURL?.absoluteString, "https://ollama.com/settings/keys",
                "Ollama 凭据页")
    assertEqual(ollama.supportsTimeSeries, true, "Ollama 有时间序列")

    let openDesign = OpenDesignBillingProvider()
    assertEqual(openDesign.credentialPageURL?.absoluteString, "https://open-design.ai/",
                "Open Design 凭据页")
    assertEqual(openDesign.supportsTimeSeries, false, "Open Design 无服务端分桶")
    assertEqual(openDesign.supportedUsageRanges, [.last24Hours, .last7Days],
                "Open Design 只支持最近 7 天窗口")
    assertEqual(minimal.supportedUsageRanges, BillingRange.allCases, "默认支持全部范围")
    assertEqual(openDesign.id, "open-design", "provider id 稳定")
    assertEqual(openDesign.credentialHint, "Open Design session token", "凭据提示")

    // 2026-11 实测：/billing/usage 的顶层 summary 与 totalCount 已消失（limit 上限 100，翻页不可行），
    // 用量明细不再可得 —— 关掉能力位后状态管理器不发这个必然失败的请求，面板也不留错误条。
    assertEqual(openDesign.supportsUsage, false, "Open Design 只查额度（用量汇总已下线）")
}

// MARK: - 最小测试替身

/// 只实现协议必选成员，用于校验默认实现（时间序列 / 凭据页 / 环境变量键名）
private struct MinimalBillingProvider: BillingProvider {
    let id: String
    var displayName: String { "Minimal" }
    var symbolName: String { "cloud" }
    var supportsModelBreakdown: Bool { false }
    var credentialHint: String { "Key" }

    func fetchBalance(credential: String) async throws -> BillingBalance {
        BillingBalance()
    }

    func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        BillingUsage(range: range, granularity: .day, start: Date(), end: Date(),
                     totals: BillingMetrics(), buckets: [])
    }
}
