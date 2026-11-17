import Foundation
import NetworkMonitorCore

// MARK: - 兜底探测 / 按范围清理 / 环境变量回落（本轮三个缺口的回归）

/// 声明了厂商原生变量名的 provider 桩（模拟 DeepSeek / Moonshot / OpenRouter）
private struct VendorKeyInstanceStubProvider: BillingProvider {
    let id: String
    let displayName: String
    var symbolName: String { "circle" }
    var supportsModelBreakdown: Bool { false }
    var supportsUsage: Bool { false }
    var minimumRefreshInterval: TimeInterval { 300 }
    var credentialHint: String { "Stub Key" }
    var environmentCredentialKey: String { "DEEPSEEK_API_KEY" }

    func fetchBalance(credential: String) async throws -> BillingBalance {
        BillingBalance(purchasedUSD: 0)
    }

    func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        BillingUsage(range: range, granularity: .day, start: Date(), end: Date(),
                     totals: BillingMetrics(), buckets: [])
    }
}

// MARK: - 1. zstd 探测链：包内自带优先，且不依赖 PATH

private func testZstdLocatorBundledFirst() {
    let directory = harnessTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }

    // 造一个「包内自带」的解压器：可执行位 + 能被 Process 跑起来的 shell 脚本
    let bundled = directory + "/Resources"
    try? FileManager.default.createDirectory(atPath: bundled, withIntermediateDirectories: true)
    let fakeZstd = bundled + "/zstd"
    try? "#!/bin/sh\nexit 0\n".write(toFile: fakeZstd, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeZstd)

    // PATH 为空、绝对候选全不存在、不问登录 shell：唯一可用来源就是包内自带
    let located = HarnessZstdLocator.locate(candidates: ["/nonexistent/a/zstd"],
                                            searchPath: nil,
                                            bundledDirectory: bundled,
                                            loginShellLookup: false)
    assertEqual(located ?? "", fakeZstd, "包内自带的 zstd 优先级最高（PATH 无关）")

    // streamer 走同一条链：可用性指向包内路径
    // （关掉内置解码：本机 /opt/homebrew 有 libzstd 时它会优先命中，这里要测的是可执行文件探测链）
    let streamer = HarnessZstdLineStreamer(executableCandidates: ["/nonexistent/a/zstd"],
                                           searchPath: nil,
                                           bundledDirectory: bundled,
                                           loginShellLookup: false,
                                           preferBuiltInDecoder: false,
                                           logger: ConsoleLogger())
    assertEqual(streamer.availability, .available(toolPath: fakeZstd), "包内自带即可用")

    // 探测记录里必须能看到包内路径（设置页要能解释「用的是哪一个」）
    let searched = HarnessZstdLocator.searchedPaths(candidates: ["/nonexistent/a/zstd"],
                                                    searchPath: nil,
                                                    bundledDirectory: bundled,
                                                    loginShellLookup: false)
    assertEqual(searched.first ?? "", fakeZstd, "探测列表首位是包内路径")

    // 三者都不可用 → toolMissing（不静默返回空数据）
    let missing = HarnessZstdLineStreamer(executableCandidates: ["/nonexistent/a/zstd"],
                                          searchPath: nil,
                                          bundledDirectory: nil,
                                          loginShellLookup: false,
                                          preferBuiltInDecoder: false,
                                          logger: ConsoleLogger())
    assertEqual(missing.availability.isAvailable, false, "无任何来源时不可用")
    print("✅ zstd 探测链（包内自带优先 / PATH 无关）works")
}

// MARK: - 2. 按范围清理：预览与实删同源，且扫描记录同事务删除

private func testPurgeScopeDays() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    assertEqual(store.migrateHarnessSchema(), true, "索引表建立")

    let now = harnessDate(2026, 10, 19, 12)
    // s1 有今天的与 20 天前的事件；s2 只有 60 天前的事件
    let today = harnessTs(2026, 10, 19, 10)
    let twentyDaysAgo = today - 20 * HarnessTokenTimeWindow.millisecondsPerDay
    let sixtyDaysAgo = today - 60 * HarnessTokenTimeWindow.millisecondsPerDay
    func event(_ session: String, _ tsMs: Int64) -> HarnessTokenEvent {
        makeEvent(sessionID: session, cwd: "/tmp/lab/" + session, tsMs: tsMs,
                  usage: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1, requestCount: 1))
    }
    func record(_ session: String) -> HarnessSessionScanRecord {
        HarnessSessionScanRecord(path: "/p/" + session, sessionID: session, size: 1, mtimeMs: 1, scannedAt: 0)
    }
    _ = store.harnessReplaceSession(record: record("s1"),
                                    events: [event("s1", today), event("s1", twentyDaysAgo)],
                                    cwd: "/tmp/lab/s1")
    _ = store.harnessReplaceSession(record: record("s2"),
                                    events: [event("s2", sixtyDaysAgo)], cwd: "/tmp/lab/s2")
    assertEqual(store.harnessEventCount(), 3, "初始 3 条事件")

    // 预览与实删必须同源：近 7 天口径只命中今天那条
    assertEqual(store.harnessPurgePreview(scope: .sinceDays(7), now: now), 1, "近 7 天预览 1 条")
    assertEqual(store.harnessPurgePreview(scope: .sinceDays(30), now: now), 2, "近 30 天预览 2 条")
    assertEqual(store.harnessPurgePreview(scope: .full, now: now), 3, "全部预览 3 条")

    // 近 30 天：删 s1 的两条（s1 今天有事件 → 扫描记录一并删掉，避免假清空）
    assertEqual(store.harnessPurge(scope: .sinceDays(30), now: now), 2, "近 30 天删除 2 条")
    assertEqual(store.harnessEventCount(), 1, "剩余 1 条（s2 的 60 天前事件）")
    let remainingRecords = store.harnessScanRecords()
    assertEqual(remainingRecords.keys.contains("/p/s1"), false, "s1 扫描记录随事件同事务删除")
    assertEqual(remainingRecords.keys.contains("/p/s2"), true, "未命中范围的 s2 扫描记录保留")
    print("✅ 按范围清理（预览同源 / 扫描记录同事务）works")
}

// MARK: - 3. 清理范围枚举与设置页选项一一对应

private func testPurgeRangeCatalogue() {
    assertEqual(HarnessPurgeRange.allCases.map(\.title),
                ["全部", "近 90 天", "近 30 天", "近 7 天"], "范围选择器四项且顺序固定")
    assertEqual(HarnessPurgeRange.all.scope, .full, "全部 = full")
    assertEqual(HarnessPurgeRange.days90.scope, .sinceDays(90), "近 90 天映射")
    assertEqual(HarnessPurgeRange.days30.scope, .sinceDays(30), "近 30 天映射")
    assertEqual(HarnessPurgeRange.days7.scope, .sinceDays(7), "近 7 天映射")
    assertEqual(HarnessPurgeRange.defaultRange, .all, "默认仍然是全部（保持旧行为）")
    assertEqual(HarnessPurgeRange.days30.confirmationText.contains("近 30 天"), true, "确认文案含天数")
    print("✅ 清理范围枚举（四项 / 默认全部）works")
}

// MARK: - 4. 环境变量键回落：实例 → provider 原生名 → 通用键

private func testEnvironmentCredentialKeyFallback() {
    // provider 没声明（等于协议默认键）→ 通用规则
    let plain = InstanceStubProvider(id: "cursor", displayName: "Cursor")
    let plainDefault = BillingProviderInstance(
        base: plain, instance: BillingInstanceID.defaultInstance(kindID: "cursor", title: "Cursor"))
    assertEqual(plainDefault.environmentCredentialKey, "BILLING_CURSOR_API_KEY", "未声明时回落通用键")

    let named = BillingProviderInstance(
        base: plain,
        instance: BillingInstanceID.namedInstance(kindID: "cursor", slug: "work", title: "工作")!)
    assertEqual(named.environmentCredentialKey, "BILLING_CURSOR_WORK_API_KEY", "未声明时命名实例追加后缀")

    // provider 声明了厂商原生名 → 默认实例直接用原生名（本轮修复的核心）
    let vendor = VendorKeyInstanceStubProvider(id: "deepseek", displayName: "DeepSeek")
    let vendorDefault = BillingProviderInstance(
        base: vendor, instance: BillingInstanceID.defaultInstance(kindID: "deepseek", title: "DeepSeek"))
    assertEqual(vendorDefault.environmentCredentialKey, "DEEPSEEK_API_KEY",
                "默认实例用 provider 声明的厂商原生变量名")

    // 命名实例：厂商键追加后缀，多个实例可各自 export
    let vendorNamed = BillingProviderInstance(
        base: vendor,
        instance: BillingInstanceID.namedInstance(kindID: "deepseek", slug: "work", title: "工作")!)
    assertEqual(vendorNamed.environmentCredentialKey, "DEEPSEEK_WORK_API_KEY",
                "命名实例在厂商原生名上追加后缀")

    // 兜底：没有 _API_KEY 后缀的键名也能追加
    assertEqual(BillingInstanceID.suffixedEnvironmentKey(base: "MOONSHOT_KEY", slug: "cn"),
                "MOONSHOT_KEY_CN", "无 _API_KEY 后缀时按通用方式追加")

    // 端到端：装饰器给出的键交给凭据存储后，环境变量真的能被读到（本轮修复的用户可见效果）
    let providerDefaultKey = vendorDefault.environmentCredentialKey
    let store = PreferencesBillingCredentialStore(
        storage: InMemoryStorage(), secrets: InMemorySecretStorage(),
        environment: [providerDefaultKey: "sk-vendor-native"],
        environmentKeyResolver: { _ in providerDefaultKey })
    assertEqual(store.credential(for: "deepseek") ?? "", "sk-vendor-native",
                "厂商原生变量名（DEEPSEEK_API_KEY）能被读到")
    let resolution = store.credentialResolution(for: "deepseek")
    assertEqual(resolution.source, .environment, "来源标记为环境变量")
    assertEqual(resolution.environmentKeys.first ?? "", "DEEPSEEK_API_KEY", "首个候选是厂商原生名")
    print("✅ 环境变量键回落（原生名优先 / 命名实例加后缀）works")
}

// MARK: - 入口

func runHarnessFollowupTests() {
    print("\n🧪 Testing zstd 探测链...")
    testZstdLocatorBundledFirst()
    print("\n🧪 Testing 按范围清理...")
    testPurgeScopeDays()
    print("\n🧪 Testing 清理范围枚举...")
    testPurgeRangeCatalogue()
    print("\n🧪 Testing 环境变量键回落...")
    testEnvironmentCredentialKeyFallback()
}
