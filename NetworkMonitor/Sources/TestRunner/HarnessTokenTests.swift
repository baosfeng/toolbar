import Foundation
import NetworkMonitorCore

// MARK: - Harness token 数据层测试（夹具 + 扫描场景）
//
// 含：单事件解析 / 缺字段容错 / 坏行跳过 / 命中率分母 0 / 周边界 /
// 增量跳过 / 空目录 / 多版本合并去重；zstd 降级与聚合口径见 HarnessTokenIndexTests.swift。

// MARK: - 测试夹具

final class StubLineStreamer: HarnessLineStreaming, @unchecked Sendable {
    let lines: [String: [String]]
    let availability: HarnessSourceAvailability

    init(
        lines: [String: [String]] = [:],
        availability: HarnessSourceAvailability = .available(toolPath: "/stub/zstd")
    ) {
        self.lines = lines
        self.availability = availability
    }

    func streamLines(from path: String, isCancelled: @Sendable () -> Bool, onLine: (Data) -> Void) throws {
        for line in lines[path] ?? [] {
            if isCancelled() { throw HarnessTokenError.cancellationRequested }
            onLine(Data(line.utf8))
        }
    }
}

final class CountingScanner: HarnessSessionScanning, @unchecked Sendable {
    let files: [HarnessSessionFile]
    let results: [String: HarnessSessionScanResult]
    let availability: HarnessSourceAvailability
    private let lock = NSLock()
    private var scanCalls = 0

    init(
        files: [HarnessSessionFile],
        results: [String: HarnessSessionScanResult],
        availability: HarnessSourceAvailability = .available(toolPath: "/stub/zstd")
    ) {
        self.files = files
        self.results = results
        self.availability = availability
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
        guard let result = results[file.path] else {
            return HarnessSessionScanResult(
                sessionID: file.sessionID, cwd: "", events: [],
                totalLines: 0, malformedLines: 0, ignoredLines: 0
            )
        }
        return result
    }
}

// MARK: - 辅助

func harnessFail(_ message: String) -> Never {
    print("❌ " + message)
    exit(1)
}

func makeTempSessionsRoot() -> String {
    let path = NSTemporaryDirectory() + "harness-tests-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

func harnessTs(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Int64 {
    Int64((harnessDate(year, month, day, hour).timeIntervalSince1970 * 1000).rounded())
}

func harnessDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    HarnessTokenTimeWindow.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        ?? Date(timeIntervalSince1970: 0)
}

func makeEvent(
    sessionID: String, cwd: String, provider: String = "p", model: String = "m",
    tsMs: Int64, usage: HarnessTokenUsage
) -> HarnessTokenEvent {
    HarnessTokenEvent(sessionID: sessionID, cwd: cwd, provider: provider, model: model, tsMs: tsMs, usage: usage)
}

func waitForIndex(_ body: (@escaping @Sendable () -> Void) -> Void) {
    let semaphore = DispatchSemaphore(value: 0)
    body { semaphore.signal() }
    if semaphore.wait(timeout: .now() + 1_800) == .timedOut {
        harnessFail("异步索引等待超时")
    }
}

// MARK: - 1. 单事件解析

private func testHarnessEventParsing() {
    let sessionLine = #"{"type":"session","version":4,"id":"s1","createdAt":1792159475947,"cwd":"/Users/me/proj"}"#
    guard case .session(let cwd) = HarnessEventParser.parse(line: Data(sessionLine.utf8)) else {
        harnessFail("session 行应解析出 cwd")
    }
    assertEqual(cwd, "/Users/me/proj", "session cwd")

    let usageLine = #"{"type":"assistant/message","seq":16,"time":1792159477767,"data":{"usage":{"inputTokens":3879,"outputTokens":196,"cacheReadTokens":8704,"cacheWriteTokens":12,"totalTokens":12791},"message":{"role":"assistant","source":{"kind":"model","provider":"deepseek-account","model":"deepseek-flash"}}}}"#
    guard case .message(let message) = HarnessEventParser.parse(line: Data(usageLine.utf8)) else {
        harnessFail("usage 行应解析出 message")
    }
    assertEqual(message.tsMs, 1792159477767, "事件时间 ms")
    assertEqual(message.provider, "deepseek-account", "provider")
    assertEqual(message.model, "deepseek-flash", "model")
    assertEqual(message.usage.uncachedInput, 3879, "未缓存输入")
    assertEqual(message.usage.output, 196, "输出")
    assertEqual(message.usage.cacheRead, 8704, "缓存读")
    assertEqual(message.usage.cacheWrite, 12, "缓存写")
    assertEqual(message.usage.requestCount, 1, "一次消息 = 一次请求")
    assertEqual(message.usage.totalTokens, 12791, "总 token")
    print("✅ Harness 单事件解析 works")
}

// MARK: - 2. usage 缺字段容错

private func testHarnessUsageTolerance() {
    let line = #"{"type":"assistant/message","time":1792159477767,"data":{"usage":{"inputTokens":10,"outputTokens":5}}}"#
    guard case .message(let message) = HarnessEventParser.parse(line: Data(line.utf8)) else {
        harnessFail("缺字段 usage 应解析成功")
    }
    assertEqual(message.usage.uncachedInput, 10, "保留未缓存输入")
    assertEqual(message.usage.output, 5, "保留输出")
    assertEqual(message.usage.cacheRead, 0, "缓存读缺省 0")
    assertEqual(message.usage.cacheWrite, 0, "缓存写缺省 0")
    assertEqual(message.provider, HarnessEventParser.unknownProvider, "provider 兜底")
    assertEqual(message.model, HarnessEventParser.unknownModel, "model 兜底")

    let noUsage = #"{"type":"assistant/message","time":1000,"data":{"message":{"role":"assistant"}}}"#
    assertEqual(HarnessEventParser.parse(line: Data(noUsage.utf8)), .ignored, "无 usage 记为忽略")

    let noTime = #"{"type":"assistant/message","data":{"usage":{"inputTokens":1}}}"#
    guard case .malformed = HarnessEventParser.parse(line: Data(noTime.utf8)) else {
        harnessFail("缺 time 应为坏行")
    }
    print("✅ Harness usage 缺字段容错 works")
}

// MARK: - 3. 坏行跳过

private func testHarnessBadLineSkipping() {
    let root = makeTempSessionsRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let path = "/stub/session.v4.jsonl.zstd"
    let lines = [
        #"{"type":"session","cwd":"/Users/me/proj"}"#,
        "这不是 JSON",
        #"{"type":"assistant/message","time":1000,"data":{"usage":{"inputTokens":1,"outputTokens":2,"cacheReadTokens":3},"message":{"source":{"provider":"p","model":"m"}}}}"#,
        "",
        #"{"type":"user/message","time":1500}"#,
    ]
    let scanner = HarnessSessionScanner(sessionsRoot: root, streamer: StubLineStreamer(lines: [path: lines]))
    let file = HarnessSessionFile(path: path, sessionID: "s1", size: 10, mtimeMs: 10)
    do {
        let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        assertEqual(result.totalLines, 5, "总行数")
        assertEqual(result.malformedLines, 1, "坏行计数")
        assertEqual(result.ignoredLines, 2, "忽略行（空行 + 无关事件）")
        assertEqual(result.events.count, 1, "仍解析出 1 条")
        assertEqual(result.cwd, "/Users/me/proj", "cwd 取 session 首行")
        assertEqual(result.events.first?.sessionID, "s1", "事件带会话 ID")
    } catch {
        harnessFail("坏行不应导致整文件失败：\(error)")
    }
    print("✅ Harness 坏行跳过 works")
}

// MARK: - 4. cacheHitRate 分母为 0

private func testHarnessCacheHitRate() {
    assertEqual(HarnessCacheHitRate.compute(cacheRead: 0, uncachedInput: 0), nil, "分母 0 返回 nil")
    assertEqual(HarnessCacheHitRate.compute(cacheRead: 10, uncachedInput: 30), 0.25, "10/40")
    assertEqual(HarnessCacheHitRate.compute(cacheRead: 5, uncachedInput: 0), 1.0, "全命中")
    print("✅ Harness cacheHitRate 分母 0 works")
}

// MARK: - 5. 周边界（周一 00:00 前后各一条）

private func testHarnessWeekBoundary() {
    let monday = harnessDate(2026, 10, 19, 0)
    let mondayMs = harnessTs(2026, 10, 19, 0)
    assertEqual(HarnessTokenTimeWindow.dayKey(tsMs: mondayMs), "2026-10-19", "周一日期键")
    assertEqual(HarnessTokenTimeWindow.isInThisWeek(tsMs: mondayMs, now: monday), true, "周一 00:00 属于本周")
    assertEqual(HarnessTokenTimeWindow.isInThisWeek(tsMs: mondayMs - 1, now: monday), false, "周一前 1ms 不属于本周")
    assertEqual(HarnessTokenTimeWindow.isToday(tsMs: mondayMs, now: monday), true, "周一 00:00 属于当天")
    assertEqual(HarnessTokenTimeWindow.isToday(tsMs: mondayMs - 1, now: monday), false, "周一前 1ms 不属于当天")
    let sunday = harnessDate(2026, 10, 18, 12)
    assertEqual(
        HarnessTokenTimeWindow.dayKey(tsMs: HarnessTokenTimeWindow.startOfWeekMs(now: sunday)),
        "2026-10-12", "周日 12:00 的本周起点是上周一"
    )
    assertEqual(
        HarnessTokenTimeWindow.dayKey(dayIndex: HarnessTokenTimeWindow.dayIndex(forTsMs: mondayMs)),
        "2026-10-19", "SQL 天序号还原日期键"
    )
    print("✅ Harness 周边界（Asia/Shanghai 周一 00:00）works")
}

// MARK: - 6. 增量跳过（同 size / mtime 不重扫）

private func testHarnessIncrementalSkip() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let path = "/stub/a/session.v4.jsonl.zstd"
    let file = HarnessSessionFile(path: path, sessionID: "s1", size: 100, mtimeMs: 5000)
    let ts = harnessTs(2026, 10, 19, 10)
    let result = HarnessSessionScanResult(
        sessionID: "s1", cwd: "/tmp/lab/exp-a",
        events: [
            makeEvent(sessionID: "s1", cwd: "/tmp/lab/exp-a", tsMs: ts,
                      usage: HarnessTokenUsage(uncachedInput: 10, output: 2, cacheRead: 30, requestCount: 1)),
            makeEvent(sessionID: "s1", cwd: "/tmp/lab/exp-a", tsMs: ts + 1000,
                      usage: HarnessTokenUsage(uncachedInput: 5, output: 1, cacheRead: 15, requestCount: 1)),
        ],
        totalLines: 3, malformedLines: 0, ignoredLines: 1
    )
    let scanner = CountingScanner(files: [file], results: [path: result])
    let service = HarnessUsageService(
        scanner: scanner, store: store, logger: ConsoleLogger(),
        nowProvider: { harnessDate(2026, 10, 19, 12) }
    )
    waitForIndex { service.rebuildIndex(completion: $0) }
    assertEqual(scanner.scans, 1, "首轮扫描 1 次")
    assertEqual(service.state, .ready, "首轮 ready")
    assertEqual(store.harnessEventCount(), 2, "首轮入库 2 条")
    let first = service.snapshot()
    assertEqual(first.indexedSessions, 1, "已索引会话数")
    assertEqual(first.totalSessions, 1, "发现会话数")
    assertEqual(first.totals.allTime.requestCount, 2, "请求数 2")

    waitForIndex { service.refreshIfNeeded(completion: $0) }
    assertEqual(scanner.scans, 1, "增量轮不重扫未变更文件")
    assertEqual(store.harnessEventCount(), 2, "事件不重复入库")
    assertEqual(service.state, .ready, "增量轮仍 ready")

    // size 变化（正在写入的会话）→ 只重扫该文件，覆盖写不产生重复
    let grown = HarnessSessionFile(path: path, sessionID: "s1", size: 120, mtimeMs: 6000)
    let scanner2 = CountingScanner(files: [grown], results: [path: result])
    let service2 = HarnessUsageService(
        scanner: scanner2, store: store, logger: ConsoleLogger(),
        nowProvider: { harnessDate(2026, 10, 19, 12) }
    )
    waitForIndex { service2.refreshIfNeeded(completion: $0) }
    assertEqual(scanner2.scans, 1, "size 变化后重扫")
    assertEqual(store.harnessEventCount(), 2, "覆盖写不重复")
    print("✅ Harness 增量跳过（size/mtime）works")
}

// MARK: - 7. 空目录

private func testHarnessEmptyDirectory() {
    let root = makeTempSessionsRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let scanner = HarnessSessionScanner(sessionsRoot: root, streamer: StubLineStreamer())
    assertEqual(scanner.availability, .available(toolPath: "/stub/zstd"), "空目录不算不可用")
    do {
        assertEqual(try scanner.discoverSessions().count, 0, "空目录 0 个会话文件")
    } catch {
        harnessFail("空目录发现应成功：\(error)")
    }

    let db = DatabaseManager()
    db.initializeInMemory()
    let service = HarnessUsageService(scanner: scanner, store: db, logger: ConsoleLogger())
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    let snapshot = service.snapshot()
    assertEqual(service.state, .ready, "空目录收敛到 ready")
    assertEqual(snapshot.totalSessions, 0, "总会话数 0")
    assertEqual(snapshot.daily.count, 0, "趋势为空")
    assertEqual(snapshot.totals.allTime.totalTokens, 0, "累计 token 0")
    assertEqual(snapshot.totals.cacheHitRate, nil, "无输入命中率 nil")

    let missing = HarnessSessionScanner(sessionsRoot: "/nonexistent-harness-root", streamer: StubLineStreamer())
    assertEqual(
        missing.availability,
        .sessionsDirectoryMissing(path: "/nonexistent-harness-root"),
        "目录缺失状态"
    )
    print("✅ Harness 空目录 works")
}

// MARK: - 9. 多版本文件合并去重（v3 / 旧版重叠内容只算一次）

private func testHarnessMultiVersionMerge() {
    let root = makeTempSessionsRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let plain = "/stub/mv/session.jsonl.zstd"
    let v3 = "/stub/mv/session.v3.jsonl.zstd"
    let head = #"{"type":"session","cwd":"/tmp/lab/mv"}"#
    func event(_ ms: Int) -> String {
        #"{"type":"assistant/message","time":\#(ms),"data":{"usage":{"inputTokens":1,"outputTokens":1,"cacheReadTokens":1},"message":{"source":{"provider":"p","model":"m"}}}}"#
    }
    let streamer = StubLineStreamer(lines: [
        plain: [head, event(2000), event(3000)],
        v3: [head, event(2000), event(3000), event(4000)],
    ])
    let scanner = HarnessSessionScanner(sessionsRoot: root, streamer: streamer)
    let file = HarnessSessionFile(path: "/stub/mv", sessionID: "mv", size: 10, mtimeMs: 10, members: [v3, plain])
    do {
        let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        assertEqual(result.events.count, 3, "重叠事件只算一次")
        assertEqual(result.totalLines, 7, "两文件行数合计")
        assertEqual(result.cwd, "/tmp/lab/mv", "cwd 来自 session 行")
    } catch {
        harnessFail("多版本合并失败：\(error)")
    }
    print("✅ Harness 多版本文件合并去重 works")
}

// MARK: - 测试入口（8 个验收场景）

func runHarnessTokenTests() {
    print("\n🧪 Testing Harness token 数据层...")
    testHarnessEventParsing()
    testHarnessUsageTolerance()
    testHarnessBadLineSkipping()
    testHarnessCacheHitRate()
    testHarnessWeekBoundary()
    testHarnessIncrementalSkip()
    testHarnessEmptyDirectory()
    testHarnessMultiVersionMerge()
    print("✅ Harness token 数据层 works")
}