import Foundation
import NetworkMonitorCore

// MARK: - 计费 provider 测试

/// 计费模块测试：格式化、模型计算、Ollama 响应解码、provider 注册表、凭据存储
///
/// 覆盖正常 / 边界 / 异常三类场景；网络层错误映射由 HTTP 状态码分支保证，
/// 这里只验证纯函数与解码逻辑，不依赖外网。
func runBillingTests() {
    print("\n🧪 Testing BillingFormat...")
    testBillingFormat()

    print("\n🧪 Testing BillingModels...")
    testBillingModels()

    print("\n🧪 Testing BillingBalance decoding...")
    testDecodeBalance()

    print("\n🧪 Testing BillingUsage decoding...")
    testDecodeUsage()

    print("\n🧪 Testing BillingProviderRegistry...")
    testProviderRegistry()

    print("\n🧪 Testing BillingCredentialStore...")
    testCredentialStore()

    print("✅ Billing 计费模块 works")
}

// MARK: - 格式化

private func testBillingFormat() {
    assertEqual(formatUSD(72.5), "$72.50", "大额两位小数")
    assertEqual(formatUSD(0.01718), "$0.017", "小额三位小数")
    assertEqual(formatUSD(0), "$0.000", "零值")
    assertEqual(formatUSD(1_234.567), "$1,234.57", "千分位 + 四舍五入")

    assertEqual(formatTokenCount(0), "0", "0 token")
    assertEqual(formatTokenCount(9_999), "9999", "不足一万原样")
    assertEqual(formatTokenCount(10_000), "1.0万", "整一万")
    assertEqual(formatTokenCount(106_000), "10.6万", "十万级")
    assertEqual(formatTokenCount(120_000_000), "1.2亿", "亿级")

    assertEqual(formatPercent(0.725), "73%", "比例四舍五入")
    assertEqual(formatPercent(0), "0%", "0%")
    assertEqual(formatPercent(1), "100%", "100%")
    assertEqual(formatPercent(1.4), "100%", "超界钳制")
}

// MARK: - 模型计算

private func testBillingModels() {
    let period = BillingPeriod(start: Date(timeIntervalSince1970: 0),
                               end: Date(timeIntervalSince1970: 20 * 86_400))
    assertEqual(period.remainingDays(at: Date(timeIntervalSince1970: 0)), 20, "周期剩余天数")
    assertEqual(period.remainingDays(at: Date(timeIntervalSince1970: 21 * 86_400)), 0, "已结束返回 0")
    assertEqual(formatPercent(period.progress(at: Date(timeIntervalSince1970: 10 * 86_400))), "50%",
                "周期进度 50%")

    let included = BillingIncludedBalance(remainingUSD: 72.5, allowanceUSD: 100, period: period)
    assertEqual(included.remainingFraction, 0.725, "剩余比例")
    let zeroAllowance = BillingIncludedBalance(remainingUSD: 10, allowanceUSD: 0)
    assertEqual(zeroAllowance.remainingFraction, 0, "总额度为 0 时比例为 0")

    let balance = BillingBalance(included: included, purchasedUSD: 25,
                                 percentLimits: [BillingPercentLimit(id: "session", title: "会话",
                                                                     remainingFraction: 0.75, resetsAt: nil)])
    assertEqual(balance.totalAvailableUSD ?? -1, 97.5, "可用总额 = 内含剩余 + 已购")
    assertEqual(balance.isEmpty, false, "有额度数据不为空")

    let purchasedOnly = BillingBalance(purchasedUSD: 25)
    assertEqual(purchasedOnly.totalAvailableUSD ?? -1, 25, "仅已购额度")

    let empty = BillingBalance()
    assertEqual(empty.totalAvailableUSD == nil, true, "无额度时可用总额为 nil")
    assertEqual(empty.isEmpty, true, "空余额")

    let clampedLimit = BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 1.8, resetsAt: nil)
    assertEqual(clampedLimit.remainingFraction, 1, "比例上限钳制")
}

// MARK: - 余额解码

private func testDecodeBalance() {
    let modernJSON = """
    {
      "included": {
        "balance_usd": 72.5,
        "allowance_usd": 100,
        "period": { "from": "2026-09-15T09:30:00Z", "until": "2026-10-15T09:30:00Z" }
      },
      "purchased": { "balance_usd": 25 }
    }
    """
    do {
        let balance = try OllamaBillingProvider.decodeBalance(from: Data(modernJSON.utf8))
        assertEqual(balance.included?.remainingUSD ?? -1, 72.5, "内含剩余额度")
        assertEqual(balance.included?.allowanceUSD ?? -1, 100, "内含总额度")
        assertNotNil(balance.included?.period, "计费周期")
        assertEqual(balance.purchasedUSD ?? -1, 25, "已购额度")
        assertEqual(balance.percentLimits.isEmpty, true, "新计划无百分比限额")
        assertEqual(balance.totalAvailableUSD ?? -1, 97.5, "可用总额")
    } catch {
        assertEqual("decode failed: \(error)", "", "余额解码不应失败")
    }

    // 遗留计划：session / weekly 百分比限额
    let legacyJSON = """
    {
      "included": {
        "session": { "remaining_percent": 75, "resets_at": "2026-10-01T07:00:00Z" },
        "weekly": { "remaining_percent": 40, "resets_at": "2026-10-05T00:00:00Z" }
      },
      "purchased": { "balance_usd": 25 }
    }
    """
    do {
        let balance = try OllamaBillingProvider.decodeBalance(from: Data(legacyJSON.utf8))
        assertEqual(balance.included == nil, true, "遗留计划无内含额度对象")
        assertEqual(balance.percentLimits.count, 2, "两条百分比限额")
        assertEqual(balance.percentLimits[0].id, "session", "session 限额")
        assertEqual(balance.percentLimits[0].remainingFraction, 0.75, "session 剩余 75%")
        assertNotNil(balance.percentLimits[0].resetsAt, "session 重置时间")
        assertEqual(balance.percentLimits[1].id, "weekly", "weekly 限额")
        assertEqual(balance.percentLimits[1].remainingFraction, 0.4, "weekly 剩余 40%")
        assertEqual(balance.purchasedUSD ?? -1, 25, "遗留计划已购额度")
    } catch {
        assertEqual("decode failed: \(error)", "", "遗留计划余额解码不应失败")
    }

    // 异常响应：缺字段仍可解码为空余额；非法 JSON 应抛错
    let emptyDecoded = try? OllamaBillingProvider.decodeBalance(from: Data("{}".utf8))
    assertEqual(emptyDecoded?.isEmpty ?? false, true, "空对象解码为空余额")

    let invalid = Data("not json".utf8)
    var threw = false
    do {
        _ = try OllamaBillingProvider.decodeBalance(from: invalid)
    } catch {
        threw = true
    }
    assertEqual(threw, true, "非法 JSON 应抛错")
}

// MARK: - 用量解码

private func testDecodeUsage() {
    let usageJSON = """
    {
      "range": "24h",
      "scope": "self",
      "granularity": "hour",
      "group_by": "model",
      "from": "2026-09-30T02:00:00Z",
      "until": "2026-10-01T02:30:00Z",
      "totals": {
        "request_count": 15,
        "usage_usd": 0.01718,
        "input_tokens": 106000,
        "cached_input_tokens": 46000,
        "output_tokens": 13600,
        "groups": [
          { "model": "glm-5.3-flash", "request_count": 12, "usage_usd": 0.0132 },
          { "model": "gpt-oss:120b", "request_count": 3, "usage_usd": 0.0040 }
        ]
      },
      "buckets": [
        { "from": "2026-09-30T12:00:00Z", "until": "2026-09-30T13:00:00Z",
          "request_count": 4, "usage_usd": 0.0052, "input_tokens": 24000,
          "cached_input_tokens": 0, "output_tokens": 3200 },
        { "from": "2026-10-01T00:00:00Z", "until": "2026-10-01T01:00:00Z",
          "request_count": 8, "usage_usd": 0.0088, "input_tokens": 64000,
          "cached_input_tokens": 40000, "output_tokens": 8000 },
        { "from": "2026-10-01T02:00:00Z", "until": "2026-10-01T02:30:00Z", "partial": true,
          "request_count": 3, "usage_usd": 0.00318, "input_tokens": 18000,
          "cached_input_tokens": 6000, "output_tokens": 2400 }
      ]
    }
    """
    do {
        let usage = try OllamaBillingProvider.decodeUsage(from: Data(usageJSON.utf8),
                                                          requestedRange: .last24Hours)
        assertEqual(usage.range, .last24Hours, "请求范围回填")
        assertEqual(usage.granularity, .hour, "小时粒度")
        assertEqual(usage.totals.requestCount, 15, "总请求数")
        assertEqual(usage.totals.usageUSD ?? -1, 0.01718, "总花费")
        assertEqual(usage.totals.inputTokens ?? -1, 106000, "输入 token")
        assertEqual(usage.totals.cachedInputTokens ?? -1, 46000, "缓存输入 token")
        assertEqual(usage.totals.outputTokens ?? -1, 13600, "输出 token")
        assertEqual(usage.groups.count, 2, "模型分组数")
        assertEqual(usage.groups[0].name, "glm-5.3-flash", "分组第一名")
        assertEqual(usage.groups[0].metrics.requestCount, 12, "分组请求数")
        assertEqual(usage.buckets.count, 3, "分桶数")
        assertEqual(usage.buckets[0].metrics.usageUSD ?? -1, 0.0052, "首桶花费")
        assertEqual(usage.buckets[2].isPartial, true, "末桶进行中")
        assertEqual(usage.buckets[0].isPartial, false, "完整桶非进行中")
        let expectedStart = ISO8601DateFormatter().date(from: "2026-09-30T02:00:00Z")
        assertEqual(usage.start, expectedStart, "范围起点")
    } catch {
        assertEqual("decode failed: \(error)", "", "用量解码不应失败")
    }

    // 非法时间戳：应抛 invalidResponse
    let badTimeJSON = """
    { "range": "7d", "granularity": "day", "from": "not-a-date", "until": "2026-10-01T00:00:00Z",
      "totals": { "request_count": 0 }, "buckets": [] }
    """
    var threw = false
    do {
        _ = try OllamaBillingProvider.decodeUsage(from: Data(badTimeJSON.utf8), requestedRange: .last7Days)
    } catch let error as BillingError {
        threw = true
        if case .invalidResponse = error {
            assertEqual(true, true, "非法时间抛 invalidResponse")
        } else {
            assertEqual("\(error)", "invalidResponse", "错误类型应为 invalidResponse")
        }
    } catch {
        threw = true
    }
    assertEqual(threw, true, "非法时间应抛错")

    // 空桶：totals 缺可选字段、buckets 为空
    let emptyJSON = """
    { "range": "30d", "granularity": "day", "from": "2026-09-01T00:00:00Z",
      "until": "2026-10-01T00:00:00Z", "totals": { "request_count": 0 }, "buckets": [] }
    """
    let emptyUsage = try? OllamaBillingProvider.decodeUsage(from: Data(emptyJSON.utf8),
                                                           requestedRange: .last30Days)
    assertEqual(emptyUsage?.granularity, .day, "天粒度")
    assertEqual(emptyUsage?.buckets.isEmpty ?? false, true, "空分桶")
    assertEqual(emptyUsage?.totals.usageUSD == nil, true, "缺失金额为 nil")
}

// MARK: - provider 注册表

private func testProviderRegistry() {
    let registry = BillingProviderRegistry()
    assertEqual(registry.isEmpty, true, "初始为空")

    registry.register(StubBillingProvider(id: "ollama"))
    registry.register(StubBillingProvider(id: "openai"))
    assertEqual(registry.all.count, 2, "注册两个 provider")
    assertEqual(registry.all.map(\.id), ["ollama", "openai"], "保持注册顺序")
    assertNotNil(registry.provider(id: "ollama"), "按 id 查找")

    // 同 id 再次注册：覆盖旧实现而不是追加
    registry.register(StubBillingProvider(id: "ollama"))
    assertEqual(registry.all.count, 2, "同 id 覆盖不新增")
    assertEqual(registry.all.filter { $0.id == "ollama" }.count, 1, "同 id 唯一")

    assertEqual(registry.provider(id: "missing") == nil, true, "未注册返回 nil")
}

// MARK: - 凭据存储

private func testCredentialStore() {
    let storage = BillingTestStorage()
    let store = PreferencesBillingCredentialStore(storage: storage, environment: [:])

    assertEqual(store.credential(for: "ollama") == nil, true, "初始无凭据")

    store.setCredential("sk-abc", for: "ollama")
    assertEqual(store.credential(for: "ollama"), "sk-abc", "写入后可读")
    assertEqual(storage.string(forKey: PreferencesBillingCredentialStore.storageKey(for: "ollama")),
                "sk-abc", "写入偏好键")

    // 首尾空白会被裁剪
    store.setCredential("  sk-def  ", for: "ollama")
    assertEqual(store.credential(for: "ollama"), "sk-def", "写入时裁剪空白")

    // 空串 / nil = 清除
    store.setCredential("", for: "ollama")
    assertEqual(store.credential(for: "ollama") == nil, true, "空串清除凭据")
    store.setCredential(nil, for: "ollama")
    assertEqual(store.credential(for: "ollama") == nil, true, "nil 清除凭据")

    // 环境变量回退：环境变量存在且偏好为空时生效
    let envStore = PreferencesBillingCredentialStore(storage: BillingTestStorage(),
                                                     environment: ["BILLING_OLLAMA_API_KEY": "env-key"])
    assertEqual(envStore.credential(for: "ollama"), "env-key", "环境变量回退")
    assertEqual(envStore.credential(for: "openai") == nil, true, "其他 provider 无回退")

    // 偏好优先于环境变量
    let mixedStorage = BillingTestStorage()
    mixedStorage.set("stored-key", forKey: PreferencesBillingCredentialStore.storageKey(for: "ollama"))
    let mixedStore = PreferencesBillingCredentialStore(storage: mixedStorage,
                                                       environment: ["BILLING_OLLAMA_API_KEY": "env-key"])
    assertEqual(mixedStore.credential(for: "ollama"), "stored-key", "偏好优先于环境变量")
}

// MARK: - 测试替身

/// 测试用 provider（只提供标识，不发请求）
private struct StubBillingProvider: BillingProvider {
    let id: String
    var displayName: String { "Stub \(id)" }
    var symbolName: String { "cloud" }
    var supportsModelBreakdown: Bool { true }
    var credentialHint: String { "Stub Key" }
    var environmentCredentialKey: String { "STUB_\(id.uppercased())_API_KEY" }

    func fetchBalance(credential: String) async throws -> BillingBalance {
        BillingBalance(purchasedUSD: 0)
    }

    func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        BillingUsage(range: range, granularity: .day, start: Date(), end: Date(),
                     totals: BillingMetrics(), buckets: [])
    }
}

/// 测试用内存存储（不污染 UserDefaults）
private final class BillingTestStorage: KeyValueStorage, @unchecked Sendable {
    private var values: [String: Any] = [:]

    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func string(forKey key: String) -> String? { values[key] as? String }
    func object(forKey key: String) -> Any? { values[key] }
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }

    func set(_ value: Int, forKey key: String) { values[key] = value }
    func set(_ value: Double, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func set(_ value: Any?, forKey key: String) { values[key] = value }

    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
