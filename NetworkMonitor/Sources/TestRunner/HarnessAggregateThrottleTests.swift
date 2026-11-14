import Foundation
import NetworkMonitorCore

// MARK: - Token 聚合降频（索引结束一次 / 无变更零聚合 / 按需补算一次）

/// 计数仓储：包住真实 DatabaseManager，数「聚合被调用了几次」
final class CountingHarnessStore: HarnessTokenRepository, @unchecked Sendable {
    private let inner: DatabaseManager
    private let lock = NSLock()
    private var aggregateCalls = 0

    init(inner: DatabaseManager) {
        self.inner = inner
    }

    var aggregates: Int {
        lock.lock()
        defer { lock.unlock() }
        return aggregateCalls
    }

    func migrateHarnessSchema() -> Bool { inner.migrateHarnessSchema() }
    func harnessScanRecords() -> [String: HarnessSessionScanRecord] { inner.harnessScanRecords() }
    func harnessReplaceSession(record: HarnessSessionScanRecord,
                               events: [HarnessTokenEvent], cwd: String) -> Bool {
        inner.harnessReplaceSession(record: record, events: events, cwd: cwd)
    }
    func harnessAggregate(now: Date) -> HarnessAggregate {
        lock.lock()
        aggregateCalls += 1
        lock.unlock()
        return inner.harnessAggregate(now: now)
    }
    func harnessEventCount() -> Int { inner.harnessEventCount() }
    func harnessClearAll() -> Bool { inner.harnessClearAll() }
}

/// 可换文件的扫描器：模拟「先 N 个变更文件，下一轮无变更，再来 M 个变更文件」
final class MutableScanner: HarnessSessionScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [HarnessSessionFile]
    private let events: [HarnessTokenEvent]

    var availability: HarnessSourceAvailability { .available(toolPath: "/stub/zstd") }

    init(files: [HarnessSessionFile], events: [HarnessTokenEvent]) {
        self.files = files
        self.events = events
    }

    func setFiles(_ newFiles: [HarnessSessionFile]) {
        lock.lock()
        files = newFiles
        lock.unlock()
    }

    func discoverSessions() throws -> [HarnessSessionFile] {
        lock.lock()
        defer { lock.unlock() }
        return files
    }

    func scan(file: HarnessSessionFile, isCancelled: @Sendable () -> Bool,
              onLinesRead: (@Sendable (Int) -> Void)?) throws -> HarnessSessionScanResult {
        HarnessSessionScanResult(sessionID: file.sessionID, cwd: "/proj/x", events: events,
                                 totalLines: events.count, malformedLines: 0, ignoredLines: 0)
    }
}

private func throttleFile(_ index: Int) -> HarnessSessionFile {
    HarnessSessionFile(path: "/sessions/s\(index)", sessionID: "s\(index)",
                       size: Int64(index), mtimeMs: Int64(index))
}

func runHarnessAggregateThrottleTests() {
    print("🧪 Testing Token 聚合降频...")
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let store = CountingHarnessStore(inner: db)
    let firstBatch = (1...4).map(throttleFile)
    let event = HarnessTokenEvent(
        sessionID: "s1", cwd: "/proj/x", provider: "p", model: "m",
        tsMs: harnessTs(2026, 10, 19),
        usage: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1,
                                 cacheWrite: 0, requestCount: 1))
    let scanner = MutableScanner(files: firstBatch, events: [event])
    let service = HarnessUsageService(scanner: scanner, store: store)

    // 1) 首轮索引：空库预热 1 次 + 索引结束 1 次 = 2 次；4 个文件不会各算一次
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    assertEqual(store.aggregates, 2, "首轮索引共聚合 2 次（预热 1 + 结束 1）")
    assertEqual(service.snapshot().indexedSessions, 4, "索引结束后快照立即有数据（无需手动刷新）")
    assertEqual(service.snapshot().totals.allTime.requestCount, 4, "4 个会话各 1 次请求")

    // 2) 无变更再刷新：零聚合
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    assertEqual(store.aggregates, 2, "无变更刷新不再聚合")

    // 3) 没有脏数据时按需补算：零聚合
    let done = DispatchSemaphore(value: 0)
    service.refreshSnapshotIfDirty()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done.signal() }
    _ = done.wait(timeout: .now() + 5)
    assertEqual(store.aggregates, 2, "无脏数据时按需补算是零查询")

    // 4) 再来 5 个变更文件：仍然只 +1 次（与文件数无关）
    scanner.setFiles(firstBatch + (5...9).map(throttleFile))
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    assertEqual(store.aggregates, 3, "5 个变更文件只多聚合 1 次")
    assertEqual(service.snapshot().indexedSessions, 9, "9 个会话全部进入快照")
}
