import Foundation

// MARK: - Token 用量门面服务

/// DSH token 用量门面服务
///
/// 线程模型：
/// - 索引动作全部在私有串行队列上执行（后台，不阻塞主线程）；同一时刻只有一轮索引
/// - 索引进行中收到的新请求**入队而不是丢弃**（`HarnessRebuildQueue`），当前轮结束后继续 drain
/// - 状态与快照由内部锁保护，snapshot() / state 可任意线程读取
/// - 数据变化后发 AppEvents.postHarnessUsageChanged()，UI 订阅刷新
///
/// 冷启动策略：UI 打开面板时 snapshot() 立即返回内存缓存（上一次索引结果），
/// 后台继续增量；索引完成后再发事件刷新，UI 不等索引。
///
/// 「一键重扫」= `rebuildIndex(scope:completion:)`：按范围清理（事件 + 扫描记录，同一事务）
/// 后全量重扫，回执告诉用户清了多少 / 扫了多少 / 索引了多少 / 耗时多久。
public final class HarnessUsageService: @unchecked Sendable, HarnessUsageServicing {
    /// 趋势数据最多保留的天数
    public static let dailyLimit = 33
    /// 项目 TopN
    public static let projectLimit = 12
    /// 模型 TopN
    public static let modelLimit = 8

    // 以下几项由 private 放宽为 internal：索引主流程已拆到 HarnessIndexRunner.swift，
    // 同模块内无其他调用方。
    /// 会话扫描器（数据源目录可热切换：设置页改目录后由组合根换新扫描器）
    private var scannerStorage: any HarnessSessionScanning
    /// 扫描器只读视图（加锁取，外部不可直接改）
    var scanner: any HarnessSessionScanning {
        lock.lock()
        defer { lock.unlock() }
        return scannerStorage
    }
    let store: any HarnessTokenRepository
    let logger: LoggingService
    let nowProvider: @Sendable () -> Date
    let queue: DispatchQueue
    let lock = NSLock()
    /// 重建请求队列（索引进行中的请求在这里排队，按最广范围合并后继续跑）
    let rebuildQueue = HarnessRebuildQueue()

    /// 当前索引状态
    private var currentState: HarnessIndexingState = .idle
    /// 最近一次聚合快照（内存缓存，跨轮次保留；快照扩展跨文件访问）
    var cachedSnapshot: HarnessUsageSnapshot?
    /// 本轮取消令牌（索引主流程读取，故 internal）
    var cancelToken = HarnessCancellationToken()
    /// 内存快照是否落后于已提交的写入（false = 复用它，不再全表聚合；快照扩展跨文件访问）
    var snapshotStale = true
    /// 是否已排入一次按需重算（重复调用合并成一次；快照扩展跨文件访问）
    var snapshotRefreshQueued = false
    /// 状态变化回调
    private var stateObserver: (@Sendable (HarnessIndexingState) -> Void)?

    /// 数据源可用性
    public var availability: HarnessSourceAvailability { scanner.availability }

    /// 数据源诊断（目录路径 + 来源 + zstd 实际路径 / 缺失原因）
    public var sourceDiagnostics: HarnessSourceDiagnostics {
        HarnessSourceDiagnostics.make(resolution: scanner.sourceResolution,
                                      availability: scanner.availability)
    }

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
        self.scannerStorage = scanner
        self.store = store
        self.logger = logger
        self.nowProvider = nowProvider
        self.queue = DispatchQueue(label: "com.bsfeng.yilan.harnessTokenIndexing", qos: .utility)
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
        return cached ?? HarnessUsageSnapshot.empty(availability: scanner.availability,
                                                    state: state,
                                                    diagnostics: sourceDiagnostics)
    }

    // MARK: - 索引入口

    public func refreshIfNeeded(completion: (@Sendable () -> Void)? = nil) {
        enqueue(scope: nil, completion: { _ in completion?() })
    }

    public func rebuildIndex(completion: (@Sendable () -> Void)? = nil) {
        enqueue(scope: .full, completion: { _ in completion?() })
    }

    public func rebuildIndex(scope: HarnessRebuildScope?,
                             completion: (@Sendable (HarnessRebuildReceipt?) -> Void)? = nil) {
        enqueue(scope: scope, completion: completion)
    }

    /// 热切换数据源（设置页改目录后调用）：换扫描器 + 标记快照过期，随后重建即可用新目录
    ///
    /// 不在这里自动开跑：调用方跟着调 `rebuildIndex(scope: .full)`，
    /// 这样「换目录成功」与「重建成功 / 失败」的回执分得清，不会互相掩盖。
    public func updateScanner(_ newScanner: any HarnessSessionScanning) {
        lock.lock()
        scannerStorage = newScanner
        lock.unlock()
        markSnapshotStale()
    }

    public func cancelIndexing() {
        lock.lock()
        let token = cancelToken
        lock.unlock()
        token.cancel()
    }

    // MARK: - 调度

    /// 入队一次索引请求并确保队列上有一个 drain 循环
    ///
    /// 为什么不再用「抢占运行权、占不到就 return」：那样用户点「重新扫描」在索引进行中
    /// 会毫无反应也不报错。现在请求进队列，本轮的 drain 循环或新排入的循环会把它跑掉；
    /// 同一轮里攒下的多个请求按最广范围合并，只跑一次。
    private func enqueue(scope: HarnessRebuildScope?,
                         completion: (@Sendable (HarnessRebuildReceipt?) -> Void)?) {
        rebuildQueue.enqueue(HarnessIndexRequest(scope: scope, completion: completion))
        queue.async { [weak self] in
            guard let self else { return }
            while let batch = self.rebuildQueue.drain() {
                let receipt = self.runIndexing(batch: batch)
                for completion in batch.completions { completion(receipt) }
            }
        }
    }

    /// 当前取消令牌（每轮开始时重置）
    func currentToken() -> HarnessCancellationToken {
        lock.lock()
        defer { lock.unlock() }
        return cancelToken
    }

    /// 重置取消令牌并返回它（每轮索引开始时调用）
    func resetCancellationToken() -> HarnessCancellationToken {
        lock.lock()
        defer { lock.unlock() }
        cancelToken = HarnessCancellationToken()
        return cancelToken
    }

    // MARK: - 状态

    /// 更新状态并同步到缓存快照，再通知观察者
    func setState(_ newState: HarnessIndexingState) {
        lock.lock()
        currentState = newState
        if let cached = cachedSnapshot {
            cachedSnapshot = cached.with(indexingState: newState)
        }
        let observer = stateObserver
        lock.unlock()
        observer?(newState)
    }

    /// 失败：保留已有快照内容，只更新状态与可用性
    ///
    /// 诊断必须在加锁前取（scanner 与 diagnostics 各自加同一把非递归锁）
    func fail(with message: String, availability: HarnessSourceAvailability) {
        setState(.failed(message: message))
        let diagnostics = sourceDiagnostics
        lock.lock()
        let cached = cachedSnapshot
        if cached == nil {
            cachedSnapshot = HarnessUsageSnapshot.empty(availability: availability,
                                                        state: .failed(message: message),
                                                        diagnostics: diagnostics)
        }
        lock.unlock()
        AppEvents.postHarnessUsageChanged()
    }
}
