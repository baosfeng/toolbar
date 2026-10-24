import Foundation
import NetworkMonitorCore

// MARK: - Harness token 按小时聚合测试
//
// 覆盖：小时归属边界 / 跨时区（UTC→上海）/ 空小时缺省 / 昨日同期隔离 / 今日小时求和 == totals.today。

// MARK: - 夹具

/// 往内存库写入一个会话的事件并登记扫描记录
private func seedHourlySession(
    _ store: any HarnessTokenRepository,
    sessionID: String,
    cwd: String,
    events: [HarnessTokenEvent]
) {
    let record = HarnessSessionScanRecord(
        path: "/stub/" + sessionID, sessionID: sessionID, size: 1, mtimeMs: 1, scannedAt: 0
    )
    _ = store.harnessReplaceSession(record: record, events: events, cwd: cwd)
}

// MARK: - 1. 小时归属边界（23:59:59.999 与次日 00:00:00.000）

private func testHourlyBoundary() {
    let lastMs = harnessTs(2026, 10, 20, 23) + 59 * 60_000 + 59_000 + 999
    let nextMs = harnessTs(2026, 10, 21, 0)
    assertEqual(HarnessTokenTimeWindow.dayKey(tsMs: lastMs), "2026-10-20", "23:59:59.999 属于当天")
    assertEqual(HarnessTokenTimeWindow.hourIndex(forTsMs: lastMs), 23, "23:59:59.999 属 23 时")
    assertEqual(HarnessTokenTimeWindow.dayKey(tsMs: nextMs), "2026-10-21", "次日 00:00 属次天")
    assertEqual(HarnessTokenTimeWindow.hourIndex(forTsMs: nextMs), 0, "次日 00:00 属 0 时")
    assertEqual(
        HarnessTokenTimeWindow.dayIndex(forTsMs: nextMs) - HarnessTokenTimeWindow.dayIndex(forTsMs: lastMs),
        1, "跨天只差 1 个天序号"
    )
    print("✅ Harness 小时归属边界 works")
}

// MARK: - 2. 跨时区（UTC 16:30 = 上海次日 00:30）

private func testHourlyCrossTimezone() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let utcDate = utc.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 16, minute: 30)) ?? Date()
    let tsMs = Int64((utcDate.timeIntervalSince1970 * 1000).rounded())
    assertEqual(HarnessTokenTimeWindow.dayKey(tsMs: tsMs), "2026-10-21", "UTC 16:30 归上海次日")
    assertEqual(HarnessTokenTimeWindow.hourIndex(forTsMs: tsMs), 0, "UTC 16:30 归上海 00 时")

    // 落到聚合层：该事件应出现在「上海次日」的 00 时槽
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    seedHourlySession(store, sessionID: "tz", cwd: "/tmp/lab/tz", events: [
        makeEvent(sessionID: "tz", cwd: "/tmp/lab/tz", tsMs: tsMs,   // 上海 00:30 → 0 时槽
                  usage: HarnessTokenUsage(uncachedInput: 11, output: 7, cacheRead: 13, requestCount: 1)),
    ])
    let aggregate = store.harnessAggregate(now: harnessDate(2026, 10, 21, 12))
    assertEqual(aggregate.todayHourly.count, 24, "固定 24 槽")
    assertEqual(aggregate.todayHourly[0].usage?.uncachedInput, 11, "次日 00 时槽命中跨时区事件")
    assertEqual(aggregate.yesterdayHourly[0].hasData, false, "昨日 00 时无数据")
    print("✅ Harness 跨时区（UTC 16:30 → 上海次日 00:30）works")
}

// MARK: - 3. 空小时缺省（不补 0）+ 未来小时缺省

private func testHourlyEmptyHours() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let now = harnessDate(2026, 10, 20, 12)
    seedHourlySession(store, sessionID: "empty", cwd: "/tmp/lab/empty", events: [
        makeEvent(sessionID: "empty", cwd: "/tmp/lab/empty", tsMs: harnessTs(2026, 10, 20, 10),
                  usage: HarnessTokenUsage(uncachedInput: 5, output: 1, cacheRead: 2, requestCount: 1)),
        // 未来小时（12:00 之后的 14 时）：数据存在但按「未来小时缺省」屏蔽
        makeEvent(sessionID: "empty", cwd: "/tmp/lab/empty", tsMs: harnessTs(2026, 10, 20, 14),
                  usage: HarnessTokenUsage(uncachedInput: 9, output: 9, cacheRead: 9, requestCount: 1)),
    ])
    let hourly = store.harnessAggregate(now: now).todayHourly
    assertEqual(hourly.count, 24, "24 槽")
    assertEqual(hourly[10].usage?.uncachedInput, 5, "10 时有数据")
    assertEqual(hourly[11].usage, nil, "11 时无数据 → nil（不补 0）")
    assertEqual(hourly[11].hasData, false, "11 时缺省标记")
    assertEqual(hourly[14].usage, nil, "未来小时（14 时）缺省")
    assertEqual(hourly.filter { $0.hasData }.count, 1, "只有 1 个有数据的小时")
    print("✅ Harness 空小时与未来小时缺省 works")
}

// MARK: - 4. 昨日同期隔离

private func testHourlyYesterdayIsolation() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let now = harnessDate(2026, 10, 20, 12)
    seedHourlySession(store, sessionID: "y", cwd: "/tmp/lab/y", events: [
        makeEvent(sessionID: "y", cwd: "/tmp/lab/y", tsMs: harnessTs(2026, 10, 19, 10),
                  usage: HarnessTokenUsage(uncachedInput: 100, output: 10, cacheRead: 1000, requestCount: 1)),
        // 昨日 23 时也属于昨日（昨日已整日结束，不应被「未来小时」屏蔽）
        makeEvent(sessionID: "y", cwd: "/tmp/lab/y", tsMs: harnessTs(2026, 10, 19, 23),
                  usage: HarnessTokenUsage(uncachedInput: 40, output: 4, cacheRead: 400, requestCount: 1)),
        makeEvent(sessionID: "y", cwd: "/tmp/lab/y", tsMs: harnessTs(2026, 10, 20, 10),
                  usage: HarnessTokenUsage(uncachedInput: 7, output: 7, cacheRead: 7, requestCount: 1)),
    ])
    let aggregate = store.harnessAggregate(now: now)
    assertEqual(aggregate.todayHourly[10].usage?.uncachedInput, 7, "今日 10 时只含今日")
    assertEqual(aggregate.yesterdayHourly[10].usage?.uncachedInput, 100, "昨日 10 时只含昨日")
    assertEqual(aggregate.yesterdayHourly[23].usage?.uncachedInput, 40, "昨日 23 时保留（昨日全天可用）")
    assertEqual(aggregate.todayHourly[23].usage, nil, "今日 23 时缺省")
    assertEqual(
        aggregate.yesterdayHourly[10].usage?.requestCount, 1, "昨日 10 时请求数不混入今日"
    )
    print("✅ Harness 昨日同期隔离 works")
}

// MARK: - 5. todayHourly 求和 == totals.today

private func testHourlySumMatchesToday() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let now = harnessDate(2026, 10, 20, 12)
    seedHourlySession(store, sessionID: "sum", cwd: "/tmp/lab/sum", events: [
        makeEvent(sessionID: "sum", cwd: "/tmp/lab/sum", tsMs: harnessTs(2026, 10, 20, 8),
                  usage: HarnessTokenUsage(uncachedInput: 10, output: 1, cacheRead: 100, cacheWrite: 2, requestCount: 1)),
        makeEvent(sessionID: "sum", cwd: "/tmp/lab/sum", tsMs: harnessTs(2026, 10, 20, 9),
                  usage: HarnessTokenUsage(uncachedInput: 20, output: 2, cacheRead: 200, cacheWrite: 3, requestCount: 1)),
        makeEvent(sessionID: "sum", cwd: "/tmp/lab/sum", tsMs: harnessTs(2026, 10, 20, 9) + 1_000,
                  usage: HarnessTokenUsage(uncachedInput: 30, output: 3, cacheRead: 300, cacheWrite: 4, requestCount: 1)),
        // 昨日事件不应进入今日小时
        makeEvent(sessionID: "sum", cwd: "/tmp/lab/sum", tsMs: harnessTs(2026, 10, 19, 9),
                  usage: HarnessTokenUsage(uncachedInput: 999, output: 99, cacheRead: 999, requestCount: 1)),
    ])
    let aggregate = store.harnessAggregate(now: now)
    let sum = aggregate.todayHourly.reduce(HarnessTokenUsage.zero) { $0.adding($1.usage ?? .zero) }
    assertEqual(sum.uncachedInput, aggregate.today.uncachedInput, "未缓存输入求和一致")
    assertEqual(sum.output, aggregate.today.output, "输出求和一致")
    assertEqual(sum.cacheRead, aggregate.today.cacheRead, "缓存读求和一致")
    assertEqual(sum.cacheWrite, aggregate.today.cacheWrite, "缓存写求和一致")
    assertEqual(sum.requestCount, aggregate.today.requestCount, "请求数求和一致")
    assertEqual(aggregate.today.uncachedInput, 60, "今日合计不含昨日")
    print("✅ Harness todayHourly 求和 == totals.today works")
}

// MARK: - 入口

func runHarnessTokenHourlyTests() {
    print("\n🧪 Testing Harness token 按小时聚合...")
    testHourlyBoundary()
    testHourlyCrossTimezone()
    testHourlyEmptyHours()
    testHourlyYesterdayIsolation()
    testHourlySumMatchesToday()
    print("✅ Harness token 按小时聚合 works")
}

// MARK: - 小时明细输出（供 --harness-index 真实数据核对）

func printHarnessHourly(snapshot: HarnessUsageSnapshot) {
    print("=== today_hourly (Asia/Shanghai) ===")
    for slot in snapshot.todayHourly {
        guard let usage = slot.usage else { continue }
        print(String(
            format: "H%02d in=%d out=%d cache=%d n=%d",
            slot.hour, usage.uncachedInput, usage.output, usage.cacheRead, usage.requestCount
        ))
    }
}
