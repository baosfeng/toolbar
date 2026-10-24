import Foundation
import NetworkMonitorCore

// MARK: - Harness token 索引测试（聚合口径 / 快照裁剪 / 显示名）
//
// 夹具与辅助函数见 HarnessTokenTests.swift。

// MARK: - 9. SQLite 聚合口径（按天 / 项目 / 模型 / 累计 / 当日 / 本周）

private func testHarnessIndexAggregation() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    assertEqual(store.migrateHarnessSchema(), true, "索引表建立")

    let expA = "/tmp/lab/exp-a"
    let demo = "/Users/me/IdeaProjects/demo"
    let expB = "/tmp/lab/exp-b"
    let sessionA = [
        makeEvent(sessionID: "s1", cwd: expA, provider: "p", model: "m1", tsMs: harnessTs(2026, 10, 19, 10),
                  usage: HarnessTokenUsage(uncachedInput: 100, output: 20, cacheRead: 300, requestCount: 1)),
        makeEvent(sessionID: "s1", cwd: expA, provider: "p", model: "m1", tsMs: harnessTs(2026, 10, 19, 11),
                  usage: HarnessTokenUsage(uncachedInput: 50, output: 10, cacheRead: 50, cacheWrite: 5, requestCount: 1)),
    ]
    let sessionB = [
        makeEvent(sessionID: "s2", cwd: demo, provider: "p", model: "m2", tsMs: harnessTs(2026, 10, 18, 10),
                  usage: HarnessTokenUsage(uncachedInput: 7, output: 3, cacheRead: 1000, requestCount: 1)),
    ]
    let sessionC = [
        makeEvent(sessionID: "s3", cwd: expB, provider: "q", model: "m3", tsMs: harnessTs(2026, 10, 10, 9),
                  usage: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1, cacheWrite: 1, requestCount: 1)),
    ]
    func record(_ path: String, _ sessionID: String) -> HarnessSessionScanRecord {
        HarnessSessionScanRecord(path: path, sessionID: sessionID, size: 1, mtimeMs: 1, scannedAt: 0)
    }
    assertEqual(store.harnessReplaceSession(record: record("/a", "s1"), events: sessionA, cwd: expA), true, "会话 A 落库")
    assertEqual(store.harnessReplaceSession(record: record("/b", "s2"), events: sessionB, cwd: demo), true, "会话 B 落库")
    assertEqual(store.harnessReplaceSession(record: record("/c", "s3"), events: sessionC, cwd: expB), true, "会话 C 落库")
    assertEqual(store.harnessEventCount(), 4, "事件总数 4")

    let aggregate = store.harnessAggregate(now: harnessDate(2026, 10, 19, 12))
    assertEqual(aggregate.allTime.uncachedInput, 158, "累计未缓存输入")
    assertEqual(aggregate.allTime.output, 34, "累计输出")
    assertEqual(aggregate.allTime.cacheRead, 1351, "累计缓存读")
    assertEqual(aggregate.allTime.cacheWrite, 6, "累计缓存写")
    assertEqual(aggregate.allTime.requestCount, 4, "累计请求数")
    assertEqual(aggregate.today.uncachedInput, 150, "今日未缓存输入")
    assertEqual(aggregate.today.requestCount, 2, "今日请求数")
    assertEqual(aggregate.thisWeek.uncachedInput, 150, "本周（周一起）未缓存输入")
    assertEqual(aggregate.thisWeek.requestCount, 2, "本周不含上周日")
    assertEqual(aggregate.daily.map { $0.day }, ["2026-10-10", "2026-10-18", "2026-10-19"], "按天聚合且空缺日不补 0")
    assertEqual(aggregate.daily.first?.usage.uncachedInput, 1, "首日用量")
    assertEqual(aggregate.projects.count, 3, "3 个项目")
    assertEqual(aggregate.projects.first?.path, demo, "按总 token 降序")
    assertEqual(aggregate.projects.first?.displayName, "demo", "容器父级省略")
    assertEqual(aggregate.projects.last?.displayName, "lab/exp-b", "非容器父级保留两级")
    assertEqual(aggregate.projects.first?.sessionCount, 1, "项目会话数")
    assertEqual(aggregate.models.first?.usage.totalTokens, 1010, "模型按总 token 降序")
    assertEqual(aggregate.models.count, 3, "3 个模型")
    assertEqual(aggregate.indexedSessions, 3, "已索引会话 3")

    _ = store.harnessReplaceSession(record: record("/a", "s1"), events: sessionA, cwd: expA)
    assertEqual(store.harnessEventCount(), 4, "同会话重扫为覆盖写")

    assertEqual(store.harnessClearAll(), true, "清空索引")
    assertEqual(store.harnessEventCount(), 0, "清空后事件 0")
    assertEqual(store.harnessAggregate(now: harnessDate(2026, 10, 19, 12)).indexedSessions, 0, "清空后会话 0")
    print("✅ Harness SQLite 聚合口径 works")
}

// MARK: - 10. 取消路径（中断后不落半截数据）

/// 卡在扫描中、等取消信号才返回的扫描器（确定性验证取消链路）
private final class BlockingScanner: HarnessSessionScanning, @unchecked Sendable {
    let files: [HarnessSessionFile]
    let availability: HarnessSourceAvailability = .available(toolPath: "/stub/zstd")
    let started = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var scanCalls = 0

    init(files: [HarnessSessionFile]) {
        self.files = files
    }

    var scans: Int {
        lock.lock()
        defer { lock.unlock() }
        return scanCalls
    }

    func discoverSessions() throws -> [HarnessSessionFile] { files }

    func scan(
        file: HarnessSessionFile,
        isCancelled: @Sendable () -> Bool,
        onLinesRead: (@Sendable (Int) -> Void)?
    ) throws -> HarnessSessionScanResult {
        lock.lock()
        scanCalls += 1
        lock.unlock()
        started.signal()
        // 等待外部取消（最多 5s，避免测试挂死）
        let deadline = Date().addingTimeInterval(5)
        while !isCancelled() && Date() < deadline {
            usleep(2_000)
        }
        throw HarnessTokenError.cancellationRequested
    }
}

private func testHarnessCancellation() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let path = "/stub/cancel/session.v4.jsonl.zstd"
    let file = HarnessSessionFile(path: path, sessionID: "s-cancel", size: 5, mtimeMs: 5)
    let scanner = BlockingScanner(files: [file])
    let service = HarnessUsageService(scanner: scanner, store: store, logger: ConsoleLogger())

    // 直接扫描：取消令牌已置位时抛 cancellationRequested，不返回半截结果
    let token = HarnessCancellationToken()
    assertEqual(token.isCancelled, false, "令牌初始未取消")
    token.cancel()
    assertEqual(token.isCancelled, true, "令牌取消后为 true")
    let scannerForToken = HarnessSessionScanner(
        sessionsRoot: makeTempSessionsRoot(), streamer: StubLineStreamer()
    )
    do {
        _ = try scannerForToken.scan(file: file, isCancelled: { token.isCancelled }, onLinesRead: nil)
        // 空行流不触发取消检查，属正常返回；这里只要求不崩溃
    } catch let error as HarnessTokenError {
        guard case .cancellationRequested = error else {
            harnessFail("取消时只应抛 cancellationRequested，实际 \(error)")
        }
    } catch {
        harnessFail("取消时不应抛其他错误：\(error)")
    }

    // 服务层：索引进行中取消 → 回到 idle，且不落任何事件/扫描记录
    let finished = DispatchSemaphore(value: 0)
    service.refreshIfNeeded { finished.signal() }
    _ = scanner.started.wait(timeout: .now() + 5)
    service.cancelIndexing()
    _ = finished.wait(timeout: .now() + 10)

    assertEqual(scanner.scans, 1, "取消发生在扫描阶段")
    assertEqual(service.state, .idle, "取消后状态回到 idle")
    assertEqual(store.harnessEventCount(), 0, "取消后不落半截事件")
    assertEqual(store.harnessScanRecords().isEmpty, true, "取消后不写扫描记录（下轮会重试）")
    print("✅ Harness 取消路径（不落半截数据）works")
}

// MARK: - 11. 快照裁剪（33 天上限 + 不补 0）+ 事件发布

private func testHarnessSnapshotLimits() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let path = "/stub/limits/session.v4.jsonl.zstd"
    let file = HarnessSessionFile(path: path, sessionID: "s40", size: 2, mtimeMs: 2)

    // 2026-09-01 起连续 40 天，每天一条事件
    var events: [HarnessTokenEvent] = []
    let calendar = HarnessTokenTimeWindow.calendar
    var cursor = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? Date()
    for _ in 0..<40 {
        let ts = Int64((cursor.timeIntervalSince1970 * 1000).rounded()) + 3_600_000
        events.append(makeEvent(
            sessionID: "s40", cwd: "/tmp/lab/trend", tsMs: ts,
            usage: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1, requestCount: 1)
        ))
        cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
    }
    let result = HarnessSessionScanResult(
        sessionID: "s40", cwd: "/tmp/lab/trend", events: events,
        totalLines: 40, malformedLines: 0, ignoredLines: 0
    )
    let scanner = CountingScanner(files: [file], results: [path: result])
    let service = HarnessUsageService(scanner: scanner, store: store, logger: ConsoleLogger())

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var get: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    let flag = Flag()
    let observer = NotificationCenter.default.addObserver(
        forName: AppEvents.harnessUsageChanged, object: nil, queue: nil
    ) { _ in flag.set() }

    waitForIndex { service.rebuildIndex(completion: $0) }
    NotificationCenter.default.removeObserver(observer)

    let snapshot = service.snapshot()
    assertEqual(snapshot.daily.count, 33, "趋势最多 33 天")
    assertEqual(snapshot.daily.first?.day, "2026-09-08", "窗口为最近 33 天")
    assertEqual(snapshot.daily.last?.day, "2026-10-10", "窗口末位为最新一天")
    assertEqual(snapshot.indexedSessions, 1, "已索引会话 1")
    // 关键口径：allTime 必须是全量累计，不能等于 33 天窗口之和
    assertEqual(snapshot.totals.allTime.requestCount, 40, "累计请求 = 全量 40（不受趋势窗口影响）")
    assertEqual(snapshot.daily.reduce(0) { $0 + $1.usage.requestCount }, 33, "daily 窗口和 = 33（仅窗口内）")
    assertEqual(snapshot.totals.allTime.requestCount > snapshot.daily.reduce(0) { $0 + $1.usage.requestCount }, true, "allTime 大于窗口和（证明取全量）")
    assertEqual(flag.get, true, "索引完成发布 harnessUsageChanged")
    print("✅ Harness 快照裁剪与事件发布 works")
}

// MARK: - 8. zstd 缺失降级

private func testHarnessZstdMissingDegradation() {
    let streamer = HarnessZstdLineStreamer(executableCandidates: ["/nonexistent/zstd"], searchPath: "", logger: ConsoleLogger())
    assertEqual(streamer.availability.isAvailable, false, "找不到 zstd 不可用")
    guard case .toolMissing(let searched) = streamer.availability else {
        harnessFail("应返回 toolMissing")
    }
    assertEqual(searched.contains("/nonexistent/zstd"), true, "记录探测路径")

    let root = makeTempSessionsRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let scanner = HarnessSessionScanner(sessionsRoot: root, streamer: streamer)
    assertEqual(scanner.availability, streamer.availability, "扫描器继承可用性")

    let file = HarnessSessionFile(path: "/stub/session.v4.jsonl.zstd", sessionID: "s1", size: 1, mtimeMs: 1)
    do {
        _ = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        harnessFail("zstd 缺失时扫描应抛错")
    } catch let error as HarnessTokenError {
        guard case .sourceUnavailable = error else {
            harnessFail("应抛 sourceUnavailable，实际 \(error)")
        }
    } catch {
        harnessFail("应抛 HarnessTokenError，实际 \(error)")
    }

    let db = DatabaseManager()
    db.initializeInMemory()
    let service = HarnessUsageService(scanner: scanner, store: db, logger: ConsoleLogger())
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    guard case .failed(let message) = service.state else {
        harnessFail("zstd 缺失状态应为 failed")
    }
    assertEqual(message.isEmpty, false, "失败原因非空")
    assertEqual(service.snapshot().sourceAvailability, streamer.availability, "快照带出可用性")
    print("✅ Harness zstd 缺失降级 works")
}

// MARK: - 测试入口

func runHarnessTokenIndexTests() {
    print("\n🧪 Testing Harness token 扫描降级 / 索引与快照...")
    testHarnessZstdMissingDegradation()
    testHarnessIndexAggregation()
    testHarnessCancellation()
    testHarnessSnapshotLimits()
    print("✅ Harness token 索引与快照 works")
}

// MARK: - 真实索引基准（人工触发：swift run --disable-sandbox --build-system native TestRunner --harness-index）

private func printHarnessBenchmark(label: String, seconds: Double, snapshot: HarnessUsageSnapshot, eventCount: Int) {
    print("=== harness-index " + label + " ===")
    print(String(format: "elapsed_seconds=%.2f", seconds))
    print("state_ready=\(snapshot.indexingState == .ready)")
    print("events=\(eventCount)")
    print("totals_uncached=\(snapshot.totals.allTime.uncachedInput)")
    print("totals_output=\(snapshot.totals.allTime.output)")
    print("totals_cache_read=\(snapshot.totals.allTime.cacheRead)")
    print("totals_cache_write=\(snapshot.totals.allTime.cacheWrite)")
    print("totals_requests=\(snapshot.totals.allTime.requestCount)")
    print("sessions_indexed=\(snapshot.indexedSessions) sessions_discovered=\(snapshot.totalSessions)")
    print("daily_days=\(snapshot.daily.count) first=\(snapshot.daily.first?.day ?? "-") last=\(snapshot.daily.last?.day ?? "-")")
    let windowRequests = snapshot.daily.reduce(0) { $0 + $1.usage.requestCount }
    print("daily_requests=" + String(windowRequests) + " alltime_requests=" + String(snapshot.totals.allTime.requestCount))
    print("cache_hit_rate=\(snapshot.totals.cacheHitRate.map { String(format: "%.4f", $0) } ?? "nil")")
    print("")
}

func runHarnessIndexBenchmark() {
    // 内存库跑，避免污染 App 正式库数据
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let streamer = HarnessZstdLineStreamer()
    print("zstd_availability=" + streamer.availability.displayMessage)
    let scanner = HarnessSessionScanner(streamer: streamer)
    let service = HarnessUsageService(scanner: scanner, store: store)

    let fullStart = Date()
    waitForIndex { service.rebuildIndex(completion: $0) }
    let fullSeconds = Date().timeIntervalSince(fullStart)
    printHarnessBenchmark(label: "full", seconds: fullSeconds, snapshot: service.snapshot(), eventCount: store.harnessEventCount())
    printHarnessHourly(snapshot: service.snapshot())

    let incrementalStart = Date()
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    let incrementalSeconds = Date().timeIntervalSince(incrementalStart)
    printHarnessBenchmark(
        label: "incremental", seconds: incrementalSeconds,
        snapshot: service.snapshot(), eventCount: store.harnessEventCount()
    )
    print(String(format: "incremental_vs_full_ratio=%.4f", fullSeconds > 0 ? incrementalSeconds / fullSeconds : 0))
}
