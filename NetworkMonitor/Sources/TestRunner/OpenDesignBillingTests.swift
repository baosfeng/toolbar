import Foundation
import NetworkMonitorCore

// MARK: - Open Design 计费 provider 测试

/// Open Design 额度 provider 测试：凭据归一化、工作区发现、额度窗口映射、
/// 用量聚合、时间窗口推导、错误映射
///
/// 全部为纯函数 / 解码测试，不依赖外网与真实 Cookie。
func runOpenDesignBillingTests() {
    print("\n🧪 Testing OpenDesign credential normalization...")
    testOpenDesignTokenNormalization()

    print("\n🧪 Testing OpenDesign workspace decoding...")
    testOpenDesignWorkspaceDecoding()

    print("\n🧪 Testing OpenDesign balance decoding...")
    testOpenDesignBalanceDecoding()

    print("\n🧪 Testing OpenDesign usage decoding...")
    testOpenDesignUsageDecoding()

    print("\n🧪 Testing OpenDesign query window...")
    testOpenDesignQueryWindow()

    print("\n🧪 Testing OpenDesign window title...")
    testOpenDesignWindowTitle()

    print("\n🧪 Testing provider capabilities...")
    testOpenDesignProviderCapabilities()

    print("✅ Open Design 额度 provider works")
}

// MARK: - 凭据归一化

private func testOpenDesignTokenNormalization() {
    let pureToken = "abc123.signature%2Fpart"

    // 纯 token 直接使用
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(pureToken), pureToken, "纯 token 原样")

    // 整条 Cookie 串：抽取目标键
    let fullCookie = "__Secure-better-auth.session_token=\(pureToken); other=1"
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(fullCookie), pureToken,
                "从 Cookie 串抽取 session token")

    // 带 Cookie: 前缀
    let withPrefix = "Cookie: __Secure-better-auth.session_token=\(pureToken)"
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(withPrefix), pureToken,
                "剥离 Cookie: 前缀")

    // 其他 Cookie 在前的顺序
    let reordered = "od_attr=xyz; __Secure-better-auth.session_token=\(pureToken); tail=2"
    assertEqual(try? OpenDesignBillingProvider.normalizedToken(reordered), pureToken,
                "目标键不在首位也能抽取")

    // 首尾空白与换行
    assertEqual(try? OpenDesignBillingProvider.normalizedToken("  \(pureToken)  "), pureToken,
                "裁剪首尾空白")

    // 空凭据：抛 missingCredential
    var emptyError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.normalizedToken("   ")
    } catch let error as BillingError {
        emptyError = error
    } catch {}
    assertEqual(emptyError, .missingCredential, "空凭据抛 missingCredential")
}

// MARK: - 工作区发现

private func testOpenDesignWorkspaceDecoding() {
    let json = """
    { "items": [ { "workspaceId": "fbpzndory1pwn0jgb6r68ed8", "workspaceName": "个人工作区",
                   "workspaceType": "personal", "role": "owner" },
                 { "workspaceId": "second-workspace", "workspaceName": "团队", "role": "member" } ] }
    """
    assertEqual(try? OpenDesignBillingProvider.decodeWorkspaceID(from: Data(json.utf8)),
                "fbpzndory1pwn0jgb6r68ed8", "取首个 workspaceId")

    // 空列表：invalidResponse
    var emptyListError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeWorkspaceID(from: Data(#"{ "items": [] }"#.utf8))
    } catch let error as BillingError {
        emptyListError = error
    } catch {}
    if case .invalidResponse = emptyListError {} else {
        assertEqual("\(String(describing: emptyListError))", "invalidResponse", "空工作区抛 invalidResponse")
    }

    // 结构不符：invalidResponse
    var malformedError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeWorkspaceID(from: Data(#"{ "unexpected": 1 }"#.utf8))
    } catch let error as BillingError {
        malformedError = error
    } catch {}
    if case .invalidResponse = malformedError {} else {
        assertEqual("\(String(describing: malformedError))", "invalidResponse", "结构不符抛 invalidResponse")
    }
}

// MARK: - 额度解码

private func testOpenDesignBalanceDecoding() {
    let json = """
    { "workspaceId": "fbpzndory1pwn0jgb6r68ed8", "generatedAt": "2026-10-23T15:20:38.939Z",
      "eligible": true, "tier": "go",
      "windows": [
        { "policyId": "model_limit_policy_yfhv1kw691dx46efu0lgxvnf",
          "durationSeconds": 18000, "resetMode": "anchored_recurring",
          "usedCredits": "123", "limitCredits": "50000", "remainingCredits": "49877",
          "windowStart": "2026-10-23T15:02:22.830Z", "resetsAt": "2026-10-23T20:02:22.830Z" },
        { "policyId": "model_limit_policy_ois3y3aw7jmck720x5bobizq",
          "durationSeconds": 604800, "resetMode": "anchored_recurring",
          "usedCredits": "76378", "limitCredits": "150000", "remainingCredits": "73622",
          "windowStart": "2026-10-20T12:02:22.830Z", "resetsAt": "2026-10-27T12:02:22.830Z" }
      ] }
    """
    guard let balance = try? OpenDesignBillingProvider.decodeBalance(from: Data(json.utf8)) else {
        assertEqual("decode failed", "", "额度解码不应失败")
        return
    }

    // 无金额维度：走「遗留计划」渲染分支
    assertEqual(balance.included == nil, true, "无内含额度")
    assertEqual(balance.purchasedUSD == nil, true, "无已购额度")
    assertEqual(balance.percentLimits.count, 2, "两个窗口")
    assertEqual(balance.isEmpty, false, "有百分比限额不为空")

    let fiveHour = balance.percentLimits[0]
    assertEqual(fiveHour.id, "model_limit_policy_yfhv1kw691dx46efu0lgxvnf", "id 取 policyId")
    assertEqual(fiveHour.title, "5 小时", "18000 秒 → 5 小时")
    assertEqual(fiveHour.usedAmount ?? -1, 123, "已用 credits")
    assertEqual(fiveHour.limitAmount ?? -1, 50_000, "限额 credits")
    assertEqual(fiveHour.unitLabel ?? "", "credits", "单位为 credits")
    assertEqual(fiveHour.hasAmountDetail, true, "有绝对值明细")
    assertEqual((fiveHour.remainingFraction * 100).rounded(), 100, "剩余 99.75% 四舍五入 100%")
    assertNotNil(fiveHour.resetsAt, "重置时间可解析")

    let weekly = balance.percentLimits[1]
    assertEqual(weekly.title, "每周", "604800 秒 → 每周")
    assertEqual((weekly.remainingFraction * 1_000).rounded() / 1_000, 0.491, "每周剩余比例 73622/150000")
    assertEqual(formatLimitUsage(used: weekly.usedAmount, limit: weekly.limitAmount,
                                 unit: weekly.unitLabel) ?? "",
                "已用 76,378 / 150,000 credits", "credits 明细文案")

    // 未开通编码计划：forbidden
    let ineligible = #"{ "eligible": false, "tier": "free", "windows": [] }"#
    var ineligibleError: BillingError?
    do {
        _ = try OpenDesignBillingProvider.decodeBalance(from: Data(ineligible.utf8))
    } catch let error as BillingError {
        ineligibleError = error
    } catch {}
    if case .forbidden = ineligibleError {} else {
        assertEqual("\(String(describing: ineligibleError))", "forbidden", "未开通抛 forbidden")
    }

    // 限额为 0：比例为 0 不崩
    let zeroLimit = """
    { "eligible": true, "windows": [ { "policyId": "p0", "durationSeconds": 3600,
      "usedCredits": "0", "limitCredits": "0", "remainingCredits": "0" } ] }
    """
    let zeroBalance = try? OpenDesignBillingProvider.decodeBalance(from: Data(zeroLimit.utf8))
    assertEqual(zeroBalance?.percentLimits.first?.remainingFraction ?? -1, 0, "限额 0 比例归零")
    assertEqual(zeroBalance?.percentLimits.first?.title ?? "", "1 小时", "3600 秒 → 1 小时")
    assertEqual(zeroBalance?.percentLimits.first?.resetsAt == nil, true, "缺 resetsAt 为 nil")
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

    // token 展示形态：格式化函数对超大 token 走「亿」
    assertEqual(formatTokenCount(2_112_637_440), "21.1亿", "缓存 token 缩写")
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

    // 7 天：从 6 天前的自然日起始，到明天 0 点结束
    let week = BillingRange.last7Days.queryWindow(now: now, calendar: calendar)
    let weekStart = calendar.dateComponents([.year, .month, .day, .hour], from: week.start)
    assertEqual(weekStart.day, 17, "7 天窗口起点为 17 日")
    assertEqual(weekStart.hour, 0, "7 天窗口起点为 0 点")
    let weekEnd = calendar.dateComponents([.day, .hour], from: week.end)
    assertEqual(weekEnd.day, 24, "7 天窗口终点为次日")
    assertEqual(weekEnd.hour, 0, "7 天窗口终点为 0 点")

    // 30 天
    let month = BillingRange.last30Days.queryWindow(now: now, calendar: calendar)
    let monthStart = calendar.dateComponents([.month, .day], from: month.start)
    assertEqual(monthStart.month, 9, "30 天窗口起点在上个月")
    assertEqual(monthStart.day, 24, "30 天窗口起点为 9/24")

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
    assertEqual(openDesign.id, "open-design", "provider id 稳定")
    assertEqual(openDesign.credentialHint, "Open Design session token", "凭据提示")
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
