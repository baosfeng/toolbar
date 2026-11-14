import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器

/// 应用协调器 — 管理所有服务的生命周期和依赖注入（唯一组合根）
///
/// 职责：
/// - 初始化所有基础设施服务与剪贴板历史链路
/// - 管理定时轮询
/// - 为 MenuBarManager 提供注入依赖
/// - 处理应用生命周期（启动/退出）
@MainActor
public final class AppCoordinator {
    // MARK: - 服务

    /// 网络速度监控
    // 放宽为 internal：`AppCoordinator+Clipboard` 的流量落盘扩展读累计字节
    var networkMonitor: (any NetworkMonitoringService)!
    /// 进程网络监控
    private let processMonitor: any ProcessNetworkMonitoringService = ProcessNetworkMonitor()
    /// 数据库（放宽为 internal：剪贴板落库回调与设置页存储统计都要读仓储）
    var database: (any AppDatabase)!
    /// 每日流量追踪
    private var trafficTracker: (any TrafficTrackingService)!
    /// 累计流量定期落盘定时器（崩溃丢失窗口压到 1 分钟）
    // 放宽为 internal：`AppCoordinator+Clipboard` 的流量落盘扩展读写
    var trafficPersistenceTimer: Timer?
    /// DSH Token 统计服务（会话扫描 + SQLite 索引 + 快照）
    private var harnessUsageService: (any HarnessUsageServicing)?
    /// 系统指标监控服务（装配细节见 AppCoordinator+SystemMonitor）
    private(set) var systemMonitor: (any SystemMonitoringService)?
    /// 屏幕活动监听（锁屏 / 休眠暂停额度刷新）
    ///
    /// 必须由组合根强持有：通知中心只持 observer 闭包，监听器被释放后
    /// 闭包里的 [weak self] 恒为 nil，额度刷新会永久失去暂停 / 恢复能力且不报错。
    var screenActivity: ScreenActivityMonitor?

    // MARK: - 剪贴板历史

    /// 剪贴板偏好（放宽为 internal：AppCoordinator+ClipboardSettings 设置页回调要读写）
    var clipboardPreferences: ClipboardPreferences!
    /// 采集器（分支 A / 分支 B 是同一个实现的两种模式；放宽为 internal：设置页切换采集模式要重启它）
    var clipboardWatcher: PasteboardWatcher!
    /// 粘贴器（写回剪贴板 + 合成 ⌘V）
    private var clipboardPaster: ClipboardPaster!
    /// Paste Stack 状态机（放宽为 internal：设置页权限查询与跳转走它）
    var clipboardStack: PasteStackController!
    /// 面板控制器
    private var clipboardPanel: ClipboardPanelController!
    /// 统一设置窗口（长期持有）
    var settingsWindow: SettingsWindow?
    /// 全局热键（放宽为 internal：设置页重新录制快捷键要重注册）
    var globalHotKey: GlobalHotKeyCenter!
    /// 截图 / 贴图链路（放宽为 internal：截图装配扩展文件要写）
    var snipController: SnipController!
    // 操作反馈实例（放宽为 internal：AppCoordinator+Feedback 装配扩展要写）
    var soundFeedback: SoundFeedback!
    var hapticFeedback: HapticFeedback!

    /// 局域网互传面板控制器
    // 放宽为 internal：AppCoordinator+Transfer 装配扩展要写
    var transferController: TransferController?
    /// 互传服务实例（设置页统计/清理要用；仅装配扩展写）
    var transferService: TransferService?

    // MARK: - 日志

    public var logger: LoggingService = AppContext.shared.logger

    // MARK: - 初始化

    public init() {
        logger.info("AppCoordinator 初始化中...")
    }

#if DEBUG
    /// 快照钩子专用（仅 DEBUG）：暴露数据库以便渲染真实剪贴板条目
    var snapshotClipboardRepository: (any ClipboardRepository)? { database }
    /// 快照钩子专用（仅 DEBUG）：暴露 Token 服务以便用真实索引结果渲染快照
    var snapshotHarnessService: (any HarnessUsageServicing)? { harnessUsageService }
#endif

    /// 启动所有服务
    func start() -> MenuBarManager {
        // 1. 数据库（同一实例满足 DatabaseService 与 ClipboardRepository）
        let databaseManager = DatabaseManager()
        databaseManager.initialize()
        database = databaseManager

        // 2. 网络监控
        let savedRx = UInt64(AppContext.shared.storage.integer(forKey: "totalRx"))
        let savedTx = UInt64(AppContext.shared.storage.integer(forKey: "totalTx"))
        networkMonitor = NetworkSpeedMonitor(totalRx: savedRx, totalTx: savedTx)

        // 3. 流量追踪
        trafficTracker = TrafficTracker(monitor: networkMonitor)

        // 4. 剪贴板历史链路
        setupClipboard(database: database)

        setupSnip()

        // 5. 局域网互传（发现层 + 传输服务 + 面板控制器）
        let transfer = makeTransferController()

        // 6. 额度页链路（provider 注册表 + 凭据存储 + 状态管理器）
        let billingRegistry = BillingProviderRegistry(providers: [
            OllamaBillingProvider(logger: logger),
            OpenDesignBillingProvider(logger: logger),
            OpencodeGoBillingProvider(logger: logger),
        ])
        // 环境变量回退键按 provider 自定义解析（Ollama 用 OLLAMA_API_KEY，其余用 BILLING_<ID>_API_KEY）
        let billingCredentials = PreferencesBillingCredentialStore(
            environmentKeyResolver: { providerID in
                billingRegistry.provider(id: providerID)?.environmentCredentialKey
                    ?? PreferencesBillingCredentialStore.defaultEnvironmentKey(for: providerID)
            })
        // 旧明文迁移：按注册表全量走一遍，不等用户点开某个 provider（详见该方法的说明）
        billingCredentials.migrateLegacyPlaintext(for: billingRegistry.all.map(\.id))
        // 额度阈值提醒（5%/4%/3%/2%/1%）：应用启动时请求通知权限
        let billingAlerts = BillingAlertService(storage: AppContext.shared.storage, logger: logger)
        billingAlerts.requestAuthorizationIfNeeded()
        let billingMonitor = BillingMonitor(registry: billingRegistry,
                                            credentialStore: billingCredentials,
                                            alertService: billingAlerts,
                                            logger: logger)
        // 6c. 统一设置窗口（六个分类页；额度页直接用上面这个 billingMonitor）
        settingsWindow = makeSettingsWindow(billingMonitor: billingMonitor)

        // 锁屏 / 休眠期间暂停额度后台轮询，解锁后立即刷新一次
        //
        // 【必须持有】监听器只被局部变量引用时，EOF 后即释放；而通知中心只持闭包，
        // 闭包里的 [weak self] 从此恒为 nil —— 额度刷新再也不会暂停 / 恢复，且无声无息
        // （现象：额度页停在旧数据、时间戳不动、进程无对外连接）。故存成协调器属性。
        let screenActivity = ScreenActivityMonitor(logger: logger)
        screenActivity.onChange = { [weak billingMonitor] active in
            if active {
                billingMonitor?.resume()
            } else {
                billingMonitor?.pause()
            }
        }
        screenActivity.start()
        self.screenActivity = screenActivity

        // 6b. DSH Token 统计链路（会话扫描 → SQLite 索引 → 快照；索引在后台队列串行执行）
        let harnessScanner = HarnessSessionScanner(streamer: HarnessZstdLineStreamer(logger: logger))
        let harnessUsage = HarnessUsageService(scanner: harnessScanner, store: databaseManager, logger: logger)
        harnessUsageService = harnessUsage

        // 6d. 系统监控链路（CPU / GPU / 内存 / 磁盘 / 温度；采样由菜单栏 1 秒链驱动）
        let systemContext = makeSystemMonitor()
        systemMonitor = systemContext.monitor

        // 7. 创建 MenuBarManager（注入依赖 + 面板所需仓储与粘贴器）
        let manager = MenuBarManager(
            networkMonitor: networkMonitor,
            processMonitor: processMonitor,
            trafficTracker: trafficTracker,
            clipboardRepository: databaseManager,
            paster: clipboardPaster,
            transferController: transfer,
            billingMonitor: billingMonitor,
            harnessUsage: harnessUsage,
            systemMonitor: systemContext.monitor,
            systemPreferences: systemContext.preferences
        )
        manager.onOpenClipboardHistory = { [weak self] in self?.clipboardPanel.toggle() }
        manager.onOpenSettings = { [weak self] section in self?.settingsWindow?.show(section: section) }

        // 8. 累计流量定期落盘（崩溃 / 强杀时也能保住当日基准）
        startTrafficPersistence()

        // 9. 启动定时轮询（由 MenuBarManager 的 setupTimer 完成）

        ClipboardImageGC.sweepOrphansAfterLaunch(repository: databaseManager, logger: logger)
        logger.info("AppCoordinator 启动完成")
        return manager
    }

    /// 应用退出前清理
    public func stop() {
        // 保存累计流量
        trafficPersistenceTimer?.invalidate()
        trafficPersistenceTimer = nil
        persistTrafficTotals()

        // 屏幕活动监听（注销通知与自检定时器）
        screenActivity?.stop()
        screenActivity = nil

        // 局域网互传
        transferController?.stop()

        // 剪贴板链路
        clipboardWatcher?.stop()
        clipboardStack?.stop()
        globalHotKey?.unregister()

        database?.close()
        logger.info("AppCoordinator 已关闭")
    }
}
