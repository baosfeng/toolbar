import Foundation
import NetworkMonitorCore

// MARK: - Token 页展示层测试（Hero / 对比条 / 分布行 / 状态带 / 格式化 / 模型装配）
//
// 配套用例见 TokenDeriveTests.swift（桶序列与分族卡）；辅助构造器 tokenSnapshot / tokenBucket 也在那边。

// MARK: - Hero 与对比条

private func testHeroAndCompare() {
    let heroToday = TokenDerive.hero(range: .today, current: sampleCurrent, previous: samplePrevious, clock: "17:05")
    assertEqual(heroToday.title, "今日总消耗", "今日 Hero 标题")
    assertEqual(heroToday.value, "6", "Hero 数值主体")
    assertEqual(heroToday.unit, "K tok", "Hero 单位")
    assertEqual(heroToday.delta, "较昨日 ↑ +100.0%", "今日 Hero 与昨日同比")
    assertEqual(heroToday.hasDelta, true, "今日 Hero 有同比")
    assertEqual(heroToday.clock, "实时 17:05", "Hero 实时时钟")

    let heroWeek = TokenDerive.hero(range: .d7, current: sampleCurrent, previous: samplePrevious, clock: "09:00")
    assertEqual(heroWeek.title, "近 7 天总消耗", "7 天 Hero 标题")
    assertEqual(heroWeek.delta, "较上期 ↑ +100.0%", "非今日 Hero 与上一周期同比")

    let heroNoDelta = TokenDerive.hero(range: .today, current: sampleCurrent, previous: .empty, clock: "08:00")
    assertEqual(heroNoDelta.hasDelta, false, "上一周期为 0 时不编同比")
    assertEqual(heroNoDelta.delta, "较昨日 —", "无同比显示破折号")

    let snapshot = tokenSnapshot()
    assertEqual(TokenDerive.compare(snapshot, current: sampleCurrent, previous: .empty, range: .today) == nil, true,
                "previous 为 0 返回 nil")
    assertEqual(TokenDerive.compare(snapshot, current: sampleCurrent, previous: samplePrevious, range: .d30) == nil, true,
                "d30 不展示对比条")
    let compare = TokenDerive.compare(snapshot, current: sampleCurrent, previous: samplePrevious, range: .today)
    assertNotNil(compare, "今日对比条可展示")
    assertEqual(compare?.currentLabel, "今日", "对比条当前标签")
    assertEqual(compare?.previousLabel, "昨日", "对比条对照标签")
    assertEqual(compare?.currentText, "6K", "对比条当前数值")
    assertEqual(compare?.previousText, "3K", "对比条对照数值")
    assertEqual(compare?.currentFraction, 1, "当前条按较大值归一")
    assertEqual(compare?.previousFraction, 0.5, "对照条按较大值归一")
    assertEqual(compare?.deltaText, "↑ +100.0%", "对比条同比文案")
    let weekCompare = TokenDerive.compare(snapshot, current: sampleCurrent, previous: samplePrevious, range: .d7)
    assertEqual(weekCompare?.currentLabel, "本周期", "7 天对比条当前标签")
    assertEqual(weekCompare?.previousLabel, "上一周期", "7 天对比条对照标签")
    print("✅ Token Hero 与对比条（今日/近 7 天文案与 delta）works")
}

// MARK: - 分布行与状态带

private func testDistroRowsAndStateBand() {
    let models = [
        HarnessModelUsage(provider: "anthropic", model: "claude",
                          usage: HarnessTokenUsage(uncachedInput: 100, output: 0, cacheRead: 300, requestCount: 2)),
        HarnessModelUsage(provider: "", model: "local",
                          usage: HarnessTokenUsage(uncachedInput: 600, output: 0, cacheRead: 0, requestCount: 1)),
    ]
    let rows = TokenDerive.modelRows(tokenSnapshot(models: models))
    assertEqual(rows.count, 2, "两个模型两行")
    assertEqual(rows[0].rank, 1, "模型行序号")
    assertEqual(rows[0].amount, "400", "模型行用量缩写")
    assertEqual(rows[0].sub, "provider anthropic · 占 40.0% · 命中 75.0%", "模型行命中率按模型自算")
    assertEqual(rows[1].provider, "", "空 provider 原样透出")
    assertEqual(rows[1].sub, "provider — · 占 60.0% · 命中 0.0%", "provider 为空时的文案")

    let projects = [HarnessProjectUsage(path: "/tmp/a", displayName: "a", sessionCount: 3,
                                        usage: HarnessTokenUsage(uncachedInput: 100, output: 0, cacheRead: 100, requestCount: 1))]
    let projectRow = TokenDerive.projectRows(tokenSnapshot(projects: projects)).first
    assertEqual(projectRow?.sub, "3 会话 · 占 100.0%", "项目行带会话数与占比")
    assertEqual(projectRow?.provider, "", "项目行不带 provider")

    // 峰值桶按下标（与真实小时桶的 index == 小时一致）
    let buckets = [tokenBucket("0时", uncached: 1, output: 0, cache: 0, request: 1),
                   tokenBucket("1时", uncached: 100, output: 0, cache: 0, request: 7),
                   tokenBucket("2时", uncached: 5, output: 0, cache: 0, request: 2)]
    let band = TokenDerive.stateBand(tokenSnapshot(), range: .today, buckets: buckets,
                                     previous: samplePrevious, current: sampleCurrent)
    assertEqual(band.count, 3, "状态带三格")
    assertEqual(band[0].title, "峰", "首格为峰值桶")
    assertEqual(band[0].value, "7 次@1时", "今日峰值取请求数的桶下标")
    assertEqual(band[1].title, "昨", "第二格为昨日合计")
    assertEqual(band[1].value, "3K", "昨日合计数值")
    assertEqual(band[2].title, "缓存", "第三格为缓存读")
    assertEqual(band[2].value, "3K", "缓存读数值")
    print("✅ Token 分布行（模型命中率 / provider 空值）与状态带 works")
}

// MARK: - 数值格式化

private func testTokenFormatting() {
    assertEqual(TokenFormatting.abbreviated(999), "999", "999 不带单位")
    assertEqual(TokenFormatting.abbreviated(1_000), "1K", "1000 → 1K")
    assertEqual(TokenFormatting.abbreviated(1_500), "1.5K", "1500 → 1.5K")
    assertEqual(TokenFormatting.tokens(1_500_000), "1.5M", "150 万 → 1.5M")
    assertEqual(TokenFormatting.tokens(10_100_000_000), "10.1B", "去尾零后 10.1B")
    assertEqual(TokenFormatting.abbreviated(0), "0", "0 不带单位")

    assertEqual(TokenFormatting.splitTokens(1_500_000).number, "1.5", "拆分出数值主体")
    assertEqual(TokenFormatting.splitTokens(1_500_000).unit, "M tok", "拆分出单位")
    assertEqual(TokenFormatting.splitTokens(398).number, "398", "无单位时数值原样")
    assertEqual(TokenFormatting.splitTokens(398).unit, "tok", "无单位时为 tok")

    assertEqual(TokenFormatting.percent(0.095), "9.5%", "占比一位小数")
    assertEqual(TokenFormatting.percent(0.095, decimals: 2), "9.50%", "占比两位小数")
    assertEqual(TokenFormatting.grouped(72_271), "72,271", "千分位")
    assertEqual(TokenFormatting.grouped(999), "999", "三位不加分隔")
    assertEqual(TokenFormatting.decimal(9.5), "9.5", "一位小数")
    assertEqual(TokenFormatting.decimal(10), "10.0", "整数补一位小数")

    assertEqual(TokenFormatting.delta(current: 100, previous: 0) == nil, true, "previous 为 0 返回 nil")
    assertEqual(TokenFormatting.delta(current: 100, previous: 100)?.text, "持平", "持平时不出方向")
    assertEqual(TokenFormatting.delta(current: 100, previous: 100)?.up, true, "持平按上行处理")
    assertEqual(TokenFormatting.delta(current: 150, previous: 100)?.text, "↑ +50.0%", "上行为 ↑ +")
    assertEqual(TokenFormatting.delta(current: 150, previous: 100)?.up, true, "上行方向")
    assertEqual(TokenFormatting.delta(current: 50, previous: 100)?.text, "↓ 50.0%", "下行为 ↓ 空格")
    assertEqual(TokenFormatting.delta(current: 50, previous: 100)?.up, false, "下行方向")

    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 24
    components.hour = 17
    components.minute = 5
    let fixedDate = HarnessTokenTimeWindow.calendar.date(from: components) ?? Date()
    assertEqual(TokenFormatting.clock(fixedDate), "17:05", "时钟补零到 HH:mm")
    assertEqual(TokenFormatting.mmdd("2026-10-24"), "10-24", "日期键取月-日")
    print("✅ Token 数值格式化（缩写边界 / 拆分 / 百分比 / 千分位 / 同比）works")
}

// MARK: - 模型装配

private func testPaneModelMake() {
    var hourly = HarnessHourlyUsage.emptyDay()
    hourly[3] = HarnessHourlyUsage(hour: 3, usage: HarnessTokenUsage(uncachedInput: 10, output: 5, cacheRead: 100, requestCount: 2))
    let snapshot = tokenSnapshot(todayHourly: hourly, indexedSessions: 3,
                                 allTime: HarnessTokenUsage(uncachedInput: 10, output: 5, cacheRead: 100, requestCount: 2))
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 24
    components.hour = 17
    components.minute = 5
    let fixedDate = HarnessTokenTimeWindow.calendar.date(from: components) ?? Date()

    let model = TokenPaneModel.make(snapshot: snapshot, range: .today, hourScope: .today, hourView: .stack,
                                    metric: .total, trendMode: .stack, now: fixedDate)
    assertEqual(model.buckets.count, 24, "今日模型 24 桶")
    assertEqual(model.bucketTitle, "今日 · 按小时 24 桶", "主图标题随范围与形态")
    assertEqual(model.hitBucketText, "24 桶", "今日按桶统计")
    assertEqual(model.hostLabel, "DSH · 3 会话", "页头会话数")
    assertEqual(model.stamp, "17:05", "页头时钟")
    assertEqual(model.hero.title, "今日总消耗", "Hero 跟随今日范围")
    assertEqual(model.cards.count, 4, "四族卡随范围")
    assertEqual(model.trendBuckets.count, 14, "天趋势固定 14 天")
    assertEqual(model.trendTitle, "天趋势 · 固定 14 天", "天趋势标题不随范围")
    assertEqual(model.hitRateFraction, TokenDerive.hitRate(TokenDerive.sum(model.buckets)), "环形图命中率与桶合计同源")
    assertEqual(model.hasData, true, "有累计数据不判空态")
    let emptyModel = TokenPaneModel.make(snapshot: tokenSnapshot(), range: .today, hourScope: .today,
                                         hourView: .stack, metric: .total, trendMode: .stack, now: fixedDate)
    assertEqual(emptyModel.hasData, false, "空快照判空态")
    print("✅ Token 展示模型装配（make 可见性 / 页头 / 趋势固定 14 天）works")
}

func runTokenPresentationTests() {
    print("\n🧪 Testing Token 页展示层（Hero / 分布 / 状态带 / 格式化 / 模型装配）...")
    testHeroAndCompare()
    testDistroRowsAndStateBand()
    testTokenFormatting()
    testPaneModelMake()
    print("✅ Token 页展示层 works")
}
