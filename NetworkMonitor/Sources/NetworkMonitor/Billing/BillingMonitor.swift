import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器

/// 额度页状态管理器 — 为每个已注册 provider 维护独立状态并并发拉取
///
/// 设计要点：
/// - 一次展示全部 provider：`states` 与注册表同序，UI 不再需要切换 provider
/// - 只依赖 Core 的计费契约（provider 注册表 / provider 协议 / 凭据存储协议），不触碰任何 UI
/// - `onUpdate` 在主线程回调最新快照，面板只负责渲染
/// - 每 provider 独立代次：切换某块的范围不会作废其它 provider 的在途请求
/// - 自动刷新 60 秒节流（`force` 跳过）；429 按 `Retry-After` 全局退避
/// - 未配置凭据的 provider 不发网络请求，快照标记为未配置态
@MainActor
final class BillingMonitor {

    // MARK: - 依赖

    let registry: BillingProviderRegistry
    // 放宽为 internal：`BillingMonitor+Fetching` 的刷新调度扩展需要读取凭据
    let credentialStore: any BillingCredentialStore
    /// 额度阈值提醒（可选；测试/未装配时为 nil）
    private let alertService: (any BillingAlerting)?
    private let logger: LoggingService

    // MARK: - 状态

    /// 全部 provider 的展示状态（与注册顺序一致）
    // 以下状态放宽为 internal：供 `BillingMonitor+Fetching` 的调度扩展读写
    var states: [ProviderState]
    /// 每 provider 的请求代次 — 只作废旧 provider 的在途结果，互不干扰
    var generations: [String: Int] = [:]
    /// 每 provider 上次发起刷新的时刻（各自节流基准，provider 间隔不同）
    var lastAttempts: [String: Date] = [:]
    /// 限流退避截止时间（429 后按 Retry-After 设置，全局生效）
    private var retryNotBefore: Date?
    /// 屏幕锁定 / 休眠时暂停后台刷新（不调接口，也不发提醒）
    private var isPaused = false
    /// 暂停期间是否已回报过快照（避免每秒重复 emit 触发布局）
    private var didReportWhilePaused = false

    /// 自动刷新最小间隔（全局下限；provider 可要求更长，见 BillingRefreshScheduler）
    static let refreshInterval: TimeInterval = BillingRefreshScheduler.minimumInterval
    /// provider 未返回 Retry-After 时的默认退避时长
    static let defaultRetryDelay: TimeInterval = 60

    // MARK: - 回调

    /// 快照更新回调（主线程）
    var onUpdate: ((Snapshot) -> Void)?

    // MARK: - 初始化

    init(registry: BillingProviderRegistry,
         credentialStore: any BillingCredentialStore,
         alertService: (any BillingAlerting)? = nil,
         logger: LoggingService = AppContext.shared.logger) {
        self.registry = registry
        self.credentialStore = credentialStore
        self.alertService = alertService
        self.logger = logger
        self.states = registry.all.map { provider in
            let descriptor = ProviderDescriptor(id: provider.id,
                                                displayName: provider.displayName,
                                                symbolName: provider.symbolName,
                                                credentialHint: provider.credentialHint,
                                                supportsModelBreakdown: provider.supportsModelBreakdown,
                                                supportsUsage: provider.supportsUsage,
                                                supportsTimeSeries: provider.supportsTimeSeries,
                                                credentialPageURL: provider.credentialPageURL)
            return ProviderState(descriptor: descriptor,
                                 range: .last24Hours,
                                 isConfigured: credentialStore.credential(for: provider.id) != nil,
                                 balance: nil,
                                 usage: nil,
                                 lastUpdated: nil,
                                 isLoading: false,
                                 errorMessage: nil)
        }
        if states.isEmpty {
            logger.warning("计费注册表为空：额度页将显示空态")
        }
    }

    // MARK: - 刷新

    /// 全量刷新：所有已配置 provider 的余额 + 用量并发拉取
    ///
    /// - Parameter force: 跳过 60 秒节流与限流退避（打开面板、保存凭据时使用）
    func refresh(force: Bool = false) {
        // 锁屏 / 休眠期间不调接口（解锁后 resume() 会强制刷新一次）
        guard !isPaused else {
            // 暂停期间仍回报一次快照：否则重启后若长期处于暂停态，额度页会整页空白
            guard !didReportWhilePaused else { return }
            didReportWhilePaused = true
            emit()
            return
        }
        didReportWhilePaused = false
        guard !states.isEmpty else {
            emit()
            return
        }
        let now = Date()
        if !force, let retryNotBefore, now < retryNotBefore { return }
        guard states.contains(where: { $0.isConfigured }) else {
            // 全部未配置：只回报未配置态，不发请求
            emit()
            return
        }
        let targets = collectFetchTargets(now: now, force: force)
        guard !targets.isEmpty else { return }
        startLoad(targets)
    }

    /// 切换某个 provider 的用量范围 — 只重拉该 provider 的用量，余额沿用
    func selectRange(_ range: BillingRange, providerID: String) {
        guard let index = states.firstIndex(where: { $0.descriptor.id == providerID }),
              states[index].range != range else { return }
        states[index].range = range

        guard states[index].isConfigured,
              let provider = registry.provider(id: providerID),
              provider.supportsUsage,
              let credential = credentialStore.credential(for: providerID) else {
            // 该 provider 只查额度、不提供用量明细：只更新选中范围，不发请求
            emit()
            return
        }
        let now = Date()
        if let retryNotBefore, now < retryNotBefore {
            // 退避期内只更新范围选择，不发起请求
            emit()
            return
        }
        let generation = nextGeneration(for: providerID)
        states[index].isLoading = true
        states[index].errorMessage = nil
        lastAttempts[providerID] = now
        emit()

        Task { @MainActor [weak self] in
            let outcome = await Self.fetchUsage(provider: provider, range: range, credential: credential)
            guard let self, self.currentGeneration(for: providerID) == generation,
                  let index = self.states.firstIndex(where: { $0.descriptor.id == providerID }) else { return }
            self.states[index].isLoading = false
            switch outcome {
            case .success(let value):
                self.states[index].usage = value
                self.states[index].lastUpdated = Date()
                self.states[index].errorMessage = nil
            case .failure(let error):
                self.handle(failure: error, providerID: providerID)
            }
            self.emit()
        }
    }

    // MARK: - 屏幕活动

    /// 屏幕锁定 / 休眠：暂停后台刷新
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        logger.debug("计费刷新暂停：屏幕锁定 / 休眠")
    }

    /// 解锁 / 唤醒：恢复并立即刷新一次
    func resume() {
        guard isPaused else { return }
        isPaused = false
        logger.debug("计费刷新恢复：屏幕可用")
        refresh(force: true)
    }

    // MARK: - 凭据

    /// 保存指定 provider 的凭据并立即刷新（空串等同于清除）
    func saveCredential(_ key: String, providerID: String) {
        guard let index = states.firstIndex(where: { $0.descriptor.id == providerID }) else { return }
        credentialStore.setCredential(key, for: providerID)
        let configured = credentialStore.credential(for: providerID) != nil
        states[index].isConfigured = configured
        states[index].errorMessage = nil
        if !configured {
            states[index].balance = nil
            states[index].usage = nil
            states[index].lastUpdated = nil
        }
        lastAttempts[providerID] = nil
        retryNotBefore = nil
        emit()
        refresh(force: true)
    }

    /// 清除指定 provider 的凭据（回到未配置态，不发请求）
    func clearCredential(providerID: String) {
        guard let index = states.firstIndex(where: { $0.descriptor.id == providerID }) else { return }
        credentialStore.setCredential(nil, for: providerID)
        states[index].isConfigured = false
        states[index].balance = nil
        states[index].usage = nil
        states[index].lastUpdated = nil
        states[index].errorMessage = nil
        states[index].isLoading = false
        lastAttempts[providerID] = nil
        _ = nextGeneration(for: providerID)
        logger.info("已清除计费凭据：\(providerID)")
        emit()
    }

    // MARK: - 请求

    /// 对到期 provider 并发发起「余额 +（可选）用量」请求
    ///
    /// 用量只在 `supportsUsage` 为真时发起：只查额度的 provider（如 OpenCode Go）没有用量接口，
    /// 发出去只会拿到 4xx 并被记成错误文案，UI 也会误显示「暂无用量」。
    private func startLoad(_ targets: [FetchTarget]) {
        emit()
        Task { @MainActor [weak self] in
            let results = await withTaskGroup(of: ProviderFetchResult.self,
                                              returning: [ProviderFetchResult].self) { group in
                for target in targets {
                    group.addTask {
                        async let balance = BillingMonitor.fetchBalance(provider: target.provider,
                                                                        credential: target.credential)
                        guard target.provider.supportsUsage else {
                            return ProviderFetchResult(id: target.id, balance: await balance, usage: nil)
                        }
                        async let usage = BillingMonitor.fetchUsage(provider: target.provider,
                                                                    range: target.range,
                                                                    credential: target.credential)
                        return ProviderFetchResult(id: target.id, balance: await balance, usage: await usage)
                    }
                }
                var collected: [ProviderFetchResult] = []
                for await result in group { collected.append(result) }
                return collected
            }
            guard let self else { return }
            self.apply(results: results, targets: targets)
            self.emit()
        }
    }

    /// 合并并发结果：成功项覆盖，失败项保留上次成功数据并记录错误文案
    private func apply(results: [ProviderFetchResult], targets: [FetchTarget]) {
        var rateLimited: TimeInterval?
        for result in results {
            guard let index = states.firstIndex(where: { $0.descriptor.id == result.id }) else { continue }
            // 期间切换了范围 / 清除了凭据：丢弃本次结果，由更新的请求接管
            guard let target = targets.first(where: { $0.id == result.id }),
                  generations[result.id] == target.generation else { continue }
            states[index].isLoading = false

            var failure: BillingError?
            switch result.balance {
            case .success(let value):
                states[index].balance = value
                alertService?.handle(balance: value,
                                     providerID: result.id,
                                     providerName: states[index].descriptor.displayName)
            case .failure(let error):
                failure = error
            }
            switch result.usage {
            case .some(.success(let value)):
                states[index].usage = value
            case .some(.failure(let error)):
                if failure == nil { failure = error }
            case .none:
                // provider 不支持用量明细：不发起请求，也不把它当失败
                states[index].usage = nil
            }

            if let failure {
                handle(failure: failure, providerID: result.id)
                if case .rateLimited(let retryAfter) = failure {
                    rateLimited = max(rateLimited ?? 0, retryAfter ?? Self.defaultRetryDelay)
                }
            } else {
                states[index].lastUpdated = Date()
                states[index].errorMessage = nil
            }
        }
        if let rateLimited {
            retryNotBefore = Date().addingTimeInterval(rateLimited)
            logger.warning("计费查询触发限流，退避 \(Int(rateLimited)) 秒")
        } else {
            retryNotBefore = nil
        }
    }

    /// 单 provider 失败处理：429 记录退避，其余记日志（UI 展示 errorMessage）
    private func handle(failure: BillingError, providerID: String) {
        if let index = states.firstIndex(where: { $0.descriptor.id == providerID }) {
            states[index].errorMessage = failure.userMessage
        }
        if case .rateLimited(let retryAfter) = failure {
            retryNotBefore = Date().addingTimeInterval(retryAfter ?? Self.defaultRetryDelay)
            logger.warning("计费查询触发限流，退避 \(Int(retryAfter ?? Self.defaultRetryDelay)) 秒")
        } else {
            logger.error("计费查询失败（\(providerID)）：\(failure.userMessage)")
        }
    }

    // MARK: - 代次

    /// 递增并返回指定 provider 的请求代次
    // 放宽为 internal：调度扩展组装 FetchTarget 时也要递增代次
    func nextGeneration(for providerID: String) -> Int {
        let next = (generations[providerID] ?? 0) + 1
        generations[providerID] = next
        return next
    }

    /// 当前代次（回调时校验结果是否过期）
    private func currentGeneration(for providerID: String) -> Int {
        generations[providerID] ?? 0
    }

    // MARK: - 回调

    /// 回调最新快照
    private func emit() {
        onUpdate?(Snapshot(states: states))
    }
}