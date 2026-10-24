import Foundation

// MARK: - Token 用量门面服务

/// DSH token 用量门面服务
///
/// 线程模型：
/// - 索引动作全部在私有串行队列上执行（后台，不阻塞主线程）；同一时刻只有一轮索引
/// - 状态与快照由内部锁保护，snapshot() / state 可任意线程读取
/// - 数据变化后发 AppEvents.postHarnessUsageChanged()，UI 订阅刷新
///
/// 冷启动策略：UI 打开面板时 snapshot() 立即返回内存缓存（上一次索引结果），
/// 后台继续增量；索引完成后再发事件刷新，UI 不等索引。
public final class HarnessUsageService: @unchecked Sendable, HarnessUsageServicing {
    /// 趋势数据最多保留的天数
    public static let dailyLimit = 33
    /// 项目 TopN
    public static let projectLimit = 12
    /// 模型 TopN
    public static let modelLimit = 8

    private let scanner: any HarnessSessionScanning
    private let store: any HarnessTokenRepository
    private let logger: LoggingService
    private let nowProvider: @Sendable () -> Date
    private let queue: DispatchQueue
    private let lock = NSLock()

    /// 当前索引状态
    private var currentState: HarnessIndexingState = .idle
    /// 最近一次聚合快照（内存缓存，跨轮次保留）
    private var cachedSnapshot: HarnessUsageSnapshot?
    /// 是否有索引在跑
    private var running = false
    /// 本轮取消令牌
    private var cancelToken = HarnessCancellationToken()
    /// 状态变化回调
    private var stateObserver: (@Sendable (HarnessIndexingState) -> Void)?

    /// 数据源可用性
    public var availability: HarnessSourceAvailability { scanner.availability }

    /// 当前索引状态
    public var state: HarnessIndexingState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    public init(
        scanner: any HarnessSessionScanning,
        store: any HarnessTokenRepository,
        logger: LoggingService = AppContext.shared.logger,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scanner = scanner
        self.store = store
        self.logger = logger
        self.nowProvider = nowProvider
        self.queue = DispatchQueue(label: "com.example.NetworkMonitor.harnessTokenIndexing", qos: .utility)
    }

    /// 状态变化回调（在索引队列上回调，UI 侧请自行切回主线程）
    public func setStateObserver(_ observer: (@Sendable (HarnessIndexingState) -> Void)?) {
        lock.lock()
        stateObserver = observer
        lock.unlock()
    }

    // MARK: - 快照读取

    public func snapshot() -> HarnessUsageSnapshot {
        lock.lock()
        let cached = cachedSnapshot
        let state = currentState
        lock.unlock()
        return cached ?? HarnessUsageSnapshot.empty(availability: scanner.availability, state: state)
    }

    // MARK: - 索引入口

    public func refreshIfNeeded(completion: (@Sendable () -> Void)? = nil) {
        enqueue(fullRebuild: false, completion: completion)
    }

    public func rebuildIndex(completion: (@Sendable () -> Void)? = nil) {
        enqueue(fullRebuild: true, completion: completion)
    }

    public func cancelIndexing() {
        lock.lock()
        let token = cancelToken
        lock.unlock()
        token.cancel()
    }

    // MARK: - 调度

    private func enqueue(fullRebuild: Bool, completion: (@Sendable () -> Void)?) {
        queue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            guard self.beginRun() else {
                self.logger.debug("Harness token 索引已在运行，跳过本次刷新")
                completion?()
                return
            }
            defer {
                self.endRun()
                completion?()
            }
            self.runIndexing(fullRebuild: fullRebuild)
        }
    }

    /// 抢占运行权：已在运行时返回 false
    private func beginRun() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return false }
        running = true
        cancelToken = HarnessCancellationToken()
        return true
    }

    private func endRun() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private func currentToken() -> HarnessCancellationToken {
        lock.lock()
        defer { lock.unlock() }
        return cancelToken
    }

    // MARK: - 索引主流程

    private func runIndexing(fullRebuild: Bool) {
        let startedAt = Date()
        let availability = scanner.availability

        guard availability.isAvailable else {
            // 降级：明确状态 + 保留已有快照，不崩溃、不返回静默空数据
            logger.warning(availability.displayMessage)
            fail(with: availability.displayMessage, availability: availability)
            return
        }
        guard store.migrateHarnessSchema() else {
            fail(with: "Harness 索引表不可用（数据库可能未就绪）", availability: availability)
            return
        }

        if fullRebuild {
            logger.info("Harness token 索引：清空后全量重建")
            _ = store.harnessClearAll()
        }

        // 冷启动先把上一轮落库结果读进内存缓存，UI 打开面板即可渲染，不必等本轮索引
        seedSnapshotIfNeeded(availability: availability)

        let files: [HarnessSessionFile]
        do {
            files = try scanner.discoverSessions()
        } catch {
            fail(with: "发现会话文件失败：" + String(describing: error), availability: availability)
            return
        }

        let records = store.harnessScanRecords()
        let changed = files.filter { file in
            guard let record = records[file.path] else { return true }
            return !record.matches(size: file.size, mtimeMs: file.mtimeMs)
        }

        // 正在写入的会话文件 size 会变，下次刷新按 (size, mtime) 重扫属预期行为
        if changed.isEmpty {
            logger.info("Harness token 增量刷新：无变更文件（共 " + String(files.count) + " 个）")
            setState(.ready)
            publishSnapshot(availability: availability, totalSessions: files.count, now: nowProvider())
            return
        }

        let token = currentToken()
        var completed = 0
        var totalEvents = 0
        var malformedLines = 0
        var failedFiles = 0
        setState(.indexing(HarnessIndexProgress(
            completedFiles: 0,
            totalFiles: changed.count,
            currentFile: "",
            parsedSessions: 0
        )))

        for file in changed {
            if token.isCancelled {
                logger.info("Harness token 索引已取消（完成 " + String(completed) + "/" + String(changed.count) + "）")
                setState(.idle)
                return
            }
            let result: HarnessSessionScanResult
            do {
                result = try scanner.scan(file: file, isCancelled: { token.isCancelled }, onLinesRead: nil)
            } catch let error as HarnessTokenError where error == .cancellationRequested {
                logger.info("Harness token 索引已取消（完成 " + String(completed) + "/" + String(changed.count) + "）")
                setState(.idle)
                return
            } catch {
                // 单文件失败只跳过该文件，不影响整体；不写扫描记录，下一轮会重试
                failedFiles += 1
                logger.warning("Harness 会话文件解析失败，已跳过: " + file.path + " — " + String(describing: error))
                continue
            }

            let record = HarnessSessionScanRecord(file: file, scannedAt: nowProvider().timeIntervalSince1970)
            if !store.harnessReplaceSession(record: record, events: result.events, cwd: result.cwd) {
                failedFiles += 1
                logger.warning("Harness 会话落库失败: " + file.path)
            }
            completed += 1
            totalEvents += result.events.count
            malformedLines += result.malformedLines
            setState(.indexing(HarnessIndexProgress(
                completedFiles: completed,
                totalFiles: changed.count,
                currentFile: file.sessionID,
                parsedSessions: completed
            )))
        }

        setState(.ready)
        publishSnapshot(availability: availability, totalSessions: files.count, now: nowProvider())

        let elapsed = Date().timeIntervalSince(startedAt)
        logger.info(String(
            format: "Harness token 索引完成：%d 个变更文件（失败 %d）/ %d 条事件 / %d 条坏行，耗时 %.2fs",
            changed.count, failedFiles, totalEvents, malformedLines, elapsed
        ))
    }

    // MARK: - 快照构建

    /// 从落库数据构建快照（并写入内存缓存 + 发事件）
    private func publishSnapshot(availability: HarnessSourceAvailability, totalSessions: Int, now: Date) {
        let aggregate = store.harnessAggregate(now: now)
        let snapshot = makeSnapshot(
            from: aggregate,
            availability: availability,
            totalSessions: totalSessions,
            lastScanAt: now
        )
        lock.lock()
        cachedSnapshot = snapshot
        lock.unlock()
        AppEvents.postHarnessUsageChanged()
    }

    /// 冷启动预热：内存无缓存时先读一次落库数据（不发事件，避免开面板时多余刷新）
    private func seedSnapshotIfNeeded(availability: HarnessSourceAvailability) {
        lock.lock()
        let hasCache = cachedSnapshot != nil
        lock.unlock()
        guard !hasCache else { return }
        let aggregate = store.harnessAggregate(now: nowProvider())
        guard aggregate.indexedSessions > 0 else { return }
        let snapshot = makeSnapshot(
            from: aggregate,
            availability: availability,
            totalSessions: aggregate.indexedSessions,
            lastScanAt: nil
        )
        lock.lock()
        cachedSnapshot = snapshot
        lock.unlock()
    }

    /// 由聚合结果裁剪出对外快照（TopN 与 33 天窗口在这里收敛）
    private func makeSnapshot(
        from aggregate: HarnessAggregate,
        availability: HarnessSourceAvailability,
        totalSessions: Int,
        lastScanAt: Date?
    ) -> HarnessUsageSnapshot {
        // 趋势只保留最近 dailyLimit 天；无数据的日子不补 0，保持空缺
        let daily = Array(aggregate.daily.suffix(Self.dailyLimit))
        let totals = HarnessUsageTotals(
            today: aggregate.today,
            thisWeek: aggregate.thisWeek,
            allTime: aggregate.allTime,
            cacheHitRate: HarnessCacheHitRate.compute(
                cacheRead: aggregate.allTime.cacheRead,
                uncachedInput: aggregate.allTime.uncachedInput
            )
        )
        return HarnessUsageSnapshot(
            totals: totals,
            daily: daily,
            todayHourly: aggregate.todayHourly,
            yesterdayHourly: aggregate.yesterdayHourly,
            projects: Array(aggregate.projects.prefix(Self.projectLimit)),
            models: Array(aggregate.models.prefix(Self.modelLimit)),
            indexedSessions: aggregate.indexedSessions,
            totalSessions: max(totalSessions, aggregate.indexedSessions),
            lastScanAt: lastScanAt,
            indexingState: state,
            sourceAvailability: availability
        )
    }

    // MARK: - 状态

    private func setState(_ newState: HarnessIndexingState) {
        lock.lock()
        currentState = newState
        if let cached = cachedSnapshot {
            cachedSnapshot = HarnessUsageSnapshot(
                totals: cached.totals,
                daily: cached.daily,
                todayHourly: cached.todayHourly,
                yesterdayHourly: cached.yesterdayHourly,
                projects: cached.projects,
                models: cached.models,
                indexedSessions: cached.indexedSessions,
                totalSessions: cached.totalSessions,
                lastScanAt: cached.lastScanAt,
                indexingState: newState,
                sourceAvailability: cached.sourceAvailability
            )
        }
        let observer = stateObserver
        lock.unlock()
        observer?(newState)
    }

    /// 失败：保留已有快照内容，只更新状态与可用性
    private func fail(with message: String, availability: HarnessSourceAvailability) {
        setState(.failed(message: message))
        lock.lock()
        let cached = cachedSnapshot
        lock.unlock()
        if cached == nil {
            lock.lock()
            cachedSnapshot = HarnessUsageSnapshot.empty(availability: availability, state: .failed(message: message))
            lock.unlock()
        }
        AppEvents.postHarnessUsageChanged()
    }
}
