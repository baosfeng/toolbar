import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器

/// 额度页状态管理器 — 拉取余额与用量、节流、限流退避与错误保留
///
/// 设计要点：
/// - 只依赖 Core 的计费契约（provider 注册表 / provider 协议 / 凭据存储协议），不触碰任何 UI
/// - `onUpdate` 在主线程回调最新快照，面板只负责渲染
/// - 并发防重入 + generation 计数：旧请求结果不会覆盖新状态
/// - 自动刷新 60 秒节流（`force` 跳过）；429 按 `Retry-After` 退避
/// - 未配置凭据时不发网络请求，快照标记为未配置态
@MainActor
final class BillingMonitor {

    // MARK: - 快照

    /// provider 展示信息 — UI 只读，避免直接持有 provider 协议实例
    struct ProviderDescriptor: Equatable {
        /// 稳定标识（凭据键 / 选择器 key）
        let id: String
        /// 展示名称
        let displayName: String
        /// SF Symbol 图标名（禁止 emoji）
        let symbolName: String
        /// 凭据输入框占位文案
        let credentialHint: String
        /// 是否提供按模型分组的明细
        let supportsModelBreakdown: Bool
        /// 是否支持时间序列（false 时 UI 隐藏用时柱状图）
        let supportsTimeSeries: Bool
        /// 凭据获取页面（配置态链接跳转目标；nil = 无在线入口）
        let credentialPageURL: URL?

        /// 兼容默认值（快照示意数据 / 测试构造用）
        init(id: String, displayName: String, symbolName: String, credentialHint: String,
             supportsModelBreakdown: Bool, supportsTimeSeries: Bool = true,
             credentialPageURL: URL? = nil) {
            self.id = id
            self.displayName = displayName
            self.symbolName = symbolName
            self.credentialHint = credentialHint
            self.supportsModelBreakdown = supportsModelBreakdown
            self.supportsTimeSeries = supportsTimeSeries
            self.credentialPageURL = credentialPageURL
        }
    }

    /// 对外快照 — 面板据此渲染状态行 / 余额卡 / 用量区 / 配置态 / 错误态
    struct Snapshot {
        /// 已注册 provider（注册顺序）
        let providers: [ProviderDescriptor]
        /// 当前选中的 provider（注册表为空时 nil）
        var selectedProviderID: String?
        /// 当前 provider 是否已配置凭据
        var isConfigured: Bool
        /// 余额（nil = 尚无成功数据）
        var balance: BillingBalance?
        /// 用量（nil = 尚无成功数据）
        var usage: BillingUsage?
        /// 当前用量范围
        var range: BillingRange
        /// 最近一次成功刷新时间
        var lastUpdated: Date?
        /// 是否正在请求
        var isLoading: Bool
        /// 错误文案（`BillingError.userMessage`），失败时保留上次成功数据
        var errorMessage: String?

        /// 当前 provider 的展示信息
        var currentProvider: ProviderDescriptor? {
            providers.first { $0.id == selectedProviderID }
        }

        /// 注册表为空（面板整页空态）
        var hasNoProvider: Bool { providers.isEmpty }
    }

    // MARK: - 依赖

    private let registry: BillingProviderRegistry
    private let credentialStore: any BillingCredentialStore
    /// 额度阈值提醒（可选；测试/未装配时为 nil）
    private let alertService: (any BillingAlerting)?
    private let logger: LoggingService

    // MARK: - 状态

    /// provider 展示信息（启动后注册表只读，构造时一次性拍平）
    private let providers: [ProviderDescriptor]
    /// 当前选中的 provider id
    private var selectedProviderID: String?

    /// 当前用量范围
    private var range: BillingRange = .last24Hours
    /// 最近一次成功拉取到的余额
    private var balance: BillingBalance?
    /// 最近一次成功拉取到的用量
    private var usage: BillingUsage?
    /// 最近一次成功刷新时间
    private var lastUpdated: Date?
    /// 是否正在请求
    private var isLoading = false
    /// 最近一次失败文案
    private var errorMessage: String?

    /// 上次发起刷新的时间（60 秒节流基准）
    private var lastRefreshStarted: Date = .distantPast
    /// 限流退避截止时间（429 后按 Retry-After 设置）
    private var retryNotBefore: Date?
    /// 请求代次 — 切换 provider / 范围后自增，旧任务结果直接丢弃
    private var generation = 0
    /// 屏幕锁定 / 休眠时暂停后台刷新（不调接口，也不发提醒）
    private var isPaused = false
    /// 暂停期间是否已回报过快照（避免每秒重复 emit 触发布局）
    private var didReportWhilePaused = false

    /// 自动刷新最小间隔（Ollama 限流 10 次/分钟，留出余量）
    static let refreshInterval: TimeInterval = 60
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
        self.providers = registry.all.map { provider in
            ProviderDescriptor(id: provider.id,
                               displayName: provider.displayName,
                               symbolName: provider.symbolName,
                               credentialHint: provider.credentialHint,
                               supportsModelBreakdown: provider.supportsModelBreakdown,
                               supportsTimeSeries: provider.supportsTimeSeries,
                               credentialPageURL: provider.credentialPageURL)
        }
        self.selectedProviderID = providers.first?.id
        if providers.isEmpty {
            logger.warning("计费注册表为空：额度页将显示空态")
        }
    }

    // MARK: - 刷新

    /// 全量刷新余额 + 用量
    ///
    /// - Parameter force: 跳过 60 秒节流与限流退避（打开面板、保存凭据、切换 provider 时使用）
    func refresh(force: Bool = false) {
        // 锁屏 / 休眠期间不调接口（解锁后 resume() 会强制刷新一次）
        guard !isPaused else {
            // 暂停期间仍回报一次快照：否则重启后若长期处于暂停态，额度页会整页空白
            // （只剩页头图标与占位符），用户会误判为「所有监控都查不了」。
            guard !didReportWhilePaused else { return }
            didReportWhilePaused = true
            emit()
            return
        }
        didReportWhilePaused = false
        guard let provider = currentProvider else {
            // 注册表为空：只回报空态，不发请求
            emit()
            return
        }
        let now = Date()
        if isLoading {
            logger.debug("计费刷新跳过：已有请求进行中")
            return
        }
        if !force, let retryNotBefore, now < retryNotBefore {
            logger.debug("计费刷新跳过：限流退避中")
            return
        }
        if !force, now.timeIntervalSince(lastRefreshStarted) < Self.refreshInterval {
            return
        }
        guard let credential = credentialStore.credential(for: provider.id) else {
            // 未配置凭据：只更新未配置态，不发起网络请求
            lastRefreshStarted = now
            applyUnconfigured()
            return
        }
        lastRefreshStarted = now
        startFullLoad(provider: provider, credential: credential)
    }

    /// 切换用量范围 — 只重拉用量（余额沿用，避免打满 10 次/分钟限流）
    func selectRange(_ newRange: BillingRange) {
        guard newRange != range else { return }
        range = newRange

        guard let provider = currentProvider,
              let credential = credentialStore.credential(for: provider.id) else {
            emit()
            return
        }
        let now = Date()
        if let retryNotBefore, now < retryNotBefore {
            // 退避期内只更新范围选择，不发起请求
            emit()
            return
        }
        generation &+= 1
        let generation = self.generation
        isLoading = true
        errorMessage = nil
        lastRefreshStarted = now
        emit()

        Task { @MainActor [weak self] in
            let outcome = await Self.fetchUsage(provider: provider, range: newRange, credential: credential)
            guard let self, self.generation == generation else { return }
            self.isLoading = false
            switch outcome {
            case .success(let value):
                self.usage = value
                self.lastUpdated = Date()
                self.errorMessage = nil
                self.retryNotBefore = nil
            case .failure(let error):
                self.handleFailure(error)
            }
            self.emit()
        }
    }

    /// 切换 provider — 清空旧数据后全量刷新
    func selectProvider(id: String) {
        guard id != selectedProviderID, registry.provider(id: id) != nil else { return }
        selectedProviderID = id
        balance = nil
        usage = nil
        lastUpdated = nil
        errorMessage = nil
        retryNotBefore = nil
        lastRefreshStarted = .distantPast
        generation &+= 1
        isLoading = false
        logger.info("切换计费 provider：\(id)")
        emit()
        refresh(force: true)
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

    /// 保存凭据并立即全量刷新（空串等同于清除）
    func saveCredential(_ key: String) {
        guard let provider = currentProvider else { return }
        credentialStore.setCredential(key, for: provider.id)
        lastRefreshStarted = .distantPast
        retryNotBefore = nil
        refresh(force: true)
    }

    /// 清除当前 provider 的凭据（回到未配置态，不发请求）
    func clearCredential() {
        guard let provider = currentProvider else { return }
        credentialStore.setCredential(nil, for: provider.id)
        logger.info("已清除计费凭据：\(provider.id)")
        applyUnconfigured()
    }

    // MARK: - 请求

    /// 发起一次全量请求（余额 + 用量并行）
    private func startFullLoad(provider: any BillingProvider, credential: String) {
        generation &+= 1
        let generation = self.generation
        let range = self.range
        isLoading = true
        errorMessage = nil
        emit()

        Task { @MainActor [weak self] in
            async let balanceOutcome = Self.fetchBalance(provider: provider, credential: credential)
            async let usageOutcome = Self.fetchUsage(provider: provider, range: range, credential: credential)
            let balanceResult = await balanceOutcome
            let usageResult = await usageOutcome
            // 代次不一致说明期间切换了 provider / 范围，丢弃本次结果
            guard let self, self.generation == generation else { return }
            self.isLoading = false
            self.apply(balanceResult: balanceResult, usageResult: usageResult, provider: provider)
            self.emit()
        }
    }

    /// 合并请求结果：成功项覆盖，失败项保留上次成功数据并记录错误文案
    private func apply(balanceResult: BillingOutcome<BillingBalance>,
                       usageResult: BillingOutcome<BillingUsage>,
                       provider: any BillingProvider) {
        var failure: BillingError?
        switch balanceResult {
        case .success(let value):
            balance = value
            // 余额成功刷新后评估阈值提醒（同一周期同一档只提醒一次）
            alertService?.handle(balance: value,
                                 providerID: provider.id,
                                 providerName: provider.displayName)
        case .failure(let error):
            failure = error
        }
        switch usageResult {
        case .success(let value):
            usage = value
        case .failure(let error):
            if failure == nil { failure = error }
        }

        if let failure {
            handleFailure(failure)
        } else {
            lastUpdated = Date()
            errorMessage = nil
            retryNotBefore = nil
        }
    }

    /// 统一失败处理：429 记录退避截止时间，其余只记日志（UI 展示 errorMessage）
    private func handleFailure(_ error: BillingError) {
        errorMessage = error.userMessage
        if case .rateLimited(let retryAfter) = error {
            let delay = retryAfter ?? Self.defaultRetryDelay
            retryNotBefore = Date().addingTimeInterval(delay)
            logger.warning("计费查询触发限流，退避 \(Int(delay)) 秒")
        } else {
            logger.error("计费查询失败：\(error.userMessage)")
        }
    }

    // MARK: - 状态

    /// 当前 provider 协议实例
    private var currentProvider: (any BillingProvider)? {
        guard let selectedProviderID else { return nil }
        return registry.provider(id: selectedProviderID)
    }

    /// 当前 provider 是否已配置凭据
    private var isConfigured: Bool {
        guard let selectedProviderID else { return false }
        return credentialStore.credential(for: selectedProviderID) != nil
    }

    /// 回到未配置态：清空余额与用量，作废在途请求
    private func applyUnconfigured() {
        generation &+= 1
        isLoading = false
        balance = nil
        usage = nil
        lastUpdated = nil
        errorMessage = nil
        emit()
    }

    /// 当前状态快照
    private var snapshot: Snapshot {
        Snapshot(providers: providers,
                 selectedProviderID: selectedProviderID,
                 isConfigured: isConfigured,
                 balance: balance,
                 usage: usage,
                 range: range,
                 lastUpdated: lastUpdated,
                 isLoading: isLoading,
                 errorMessage: errorMessage)
    }

    /// 回调最新快照
    private func emit() {
        onUpdate?(snapshot)
    }
}
