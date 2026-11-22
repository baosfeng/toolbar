import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureBilling
import NetworkMonitorFeatureClipboard
import NetworkMonitorFeatureFeedback
import NetworkMonitorFeatureSmoothScroll

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
    // 放宽为 internal：装配阶段（AppAssemblyStages）跨文件构造 MenuBarManager 时要读
    let processMonitor: any ProcessNetworkMonitoringService = ProcessNetworkMonitor()
    /// 数据库（放宽为 internal：剪贴板落库回调与设置页存储统计都要读仓储）
    var database: (any AppDatabase)!
    /// 每日流量追踪
    // 放宽为 internal：装配阶段（AppAssemblyStages）跨文件写入并注入 MenuBarManager
    var trafficTracker: (any TrafficTrackingService)!
    /// 累计流量定期落盘定时器（崩溃丢失窗口压到 1 分钟）
    // 放宽为 internal：`AppCoordinator+Clipboard` 的流量落盘扩展读写
    var trafficPersistenceTimer: Timer?
    /// DSH Token 统计服务（设置页「Token 用量」要读诊断 / 事件数并触发重扫）
    var harnessUsageService: (any HarnessUsageServicing)?
    /// Token 后台自动增量索引调度器（tokenStage 产出、teardown 停止）
    ///
    /// 必须强持有：定时器与屏幕活动订阅都在它身上，释放即静默失效（后台再也不扫）。
    var tokenAutoIndexScheduler: TokenAutoIndexScheduler?
    /// 系统指标监控服务（装配细节见 AppCoordinator+SystemMonitor）
    // 放宽为 internal：装配阶段（AppAssemblyStages+Features）跨文件写入
    var systemMonitor: (any SystemMonitoringService)?
    /// 屏幕活动监听（锁屏 / 休眠暂停额度刷新）
    ///
    /// 必须强持有：通知中心只持 observer 闭包，监听器被释放后闭包里的 [weak self] 恒为 nil，
    /// 额度刷新会永久失去暂停 / 恢复能力且不报错。
    var screenActivity: ScreenActivityMonitor?

    // MARK: - 剪贴板历史

    /// 剪贴板偏好（放宽为 internal：AppCoordinator+ClipboardSettings 设置页回调要读写）
    var clipboardPreferences: ClipboardPreferences!
    /// 采集器（分支 A / 分支 B 是同一个实现的两种模式；放宽为 internal：设置页切换采集模式要重启它）
    var clipboardWatcher: PasteboardWatcher!
    /// 粘贴器（写回剪贴板 + 合成 ⌘V）
    // 放宽为 internal：`AppCoordinator+Clipboard` 的剪贴板装配扩展要写
    var clipboardPaster: ClipboardPaster!
    /// Paste Stack 状态机（放宽为 internal：设置页权限查询与跳转走它）
    var clipboardStack: PasteStackController!
    /// 面板控制器
    // 放宽为 internal：`AppCoordinator+Clipboard` 的装配与热键回调要读写
    var clipboardPanel: ClipboardPanelController!
    /// 图片文字识别调度（采集回调里入队；放宽为 internal 供装配扩展写、停止时丢弃在途结果）
    var clipboardOCR: ClipboardOCRCoordinator!
    /// 统一设置窗口（长期持有；六个功能页按需装配）
    var settingsWindow: SettingsWindow?
    /// 更新检查服务（关于页与启动自动检查共用同一实例）
    var updateCheck: UpdateCheckService?
    /// 全局热键（设置页重新录制快捷键要重注册）
    var globalHotKey: GlobalHotKeyCenter!
    /// 截图 / 贴图链路（截图装配扩展文件要写）
    var snipController: SnipController!
    // 操作反馈实例（AppCoordinator+Feedback 装配扩展要写）
    var soundFeedback: SoundFeedback!
    var hapticFeedback: HapticFeedback!
    /// 通知与音效偏好（事件表六行的唯一读写入口）
    var notificationPreferences: NotificationPreferences!
    /// 应用内音效库（系统音效清单 + 自定义音效目录）
    var soundLibrary: NotificationSoundLibrary!
    /// 应用内音效播放器
    var soundPlayer: NotificationSoundPlayer!
    /// 系统通知入口（额度 / 传输等全部系统通知的唯一出口）；隐式解包写在括号外——`any P!` 在 Swift 6.3 会被拒
    var notificationService: (any NotificationServicing)!

    /// 系统权限链路（三类权限的唯一读取与请求入口；设置页与面板页脚共用同一份快照）
    /// 放宽为 internal：权限接线扩展与设置页工厂要用
    var permissionChain: (any SystemPermissionProviding)?
    /// 鼠标滚轮平滑引擎（可选模块，默认关闭；关着时实例存在但状态为 idle）
    // 放宽为 internal：装配阶段与设置页（热生效 / 状态说明）跨文件读写
    var scrollSmoothingEngine: ScrollSmoothingEngine?
    /// 局域网互传面板控制器
    // 放宽为 internal：AppCoordinator+Transfer 装配扩展要写
    var transferController: TransferController?
    /// 互传服务实例（设置页统计/清理要用；仅装配扩展写）
    var transferService: TransferService?

    // MARK: - 装配

    /// 当前装配器（停止时按它记录的启动顺序逆序清理）
    private var compositionHandle: AppComposition?
    /// 额度状态管理器（设置页 / 面板 / 屏幕活动阶段共用同一实例）
    var billingMonitor: BillingMonitor?
    /// 菜单栏管理器（菜单栏阶段产出；start() 的返回值）
    // 放宽为 internal：装配阶段（AppAssemblyStages+Features）跨文件写入
    var menuBarManager: MenuBarManager?
    /// 数据库具体实现
    ///
    /// 组合根唯一允许持有具体类型的例外：Token 统计与剪贴板清理要的是
    /// DatabaseService & ClipboardRepository & HarnessTokenRepository 的组合能力，
    /// 现有 AppDatabase 组合别名还没并入 HarnessTokenRepository，按协议取会丢能力。
    var databaseManager: DatabaseManager?
    /// 系统监控偏好（与 monitor 同源，菜单栏阶段要一起注入）
    var menuBarSystemContext: (monitor: any SystemMonitoringService,
                               preferences: SystemMonitorPreferences)?

    /// 全应用共享的 HTTP 出网实例 —— 组合根唯一构造点，按协议注入各调用方
    ///
    /// 额度 provider 与更新检查 / 安装包下载原先各自 new 传输层，URLSession 配置与
    /// 连接池因此散在多处；收敛到这里后，provider 内部只声明依赖、不再自建。
    let httpTransport: any HTTPTransport = URLSessionHTTPTransport(session: .shared,
                                                                   logger: AppContext.shared.logger)

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
    ///
    /// 只做两件事：声明装配阶段（顺序与依赖见 `AppAssemblyPlan`）、交给装配器执行。
    /// 阶段顺序由 requires 拓扑排序给出，声明错误（重名 / 缺依赖 / 成环）启动即失败。
    func start() -> MenuBarManager {
        let composition = AppComposition(stages: assembleStages, logger: logger)
        compositionHandle = composition
        var environment = AppEnvironment(coordinator: self)
        do {
            try composition.run(in: &environment)
        } catch {
            // 声明错误（重名 / 缺依赖 / 成环）是编码错误，测试期就该判红；
            // 运行时只剩「明确失败」一种处置——静默跳过会得到「少了某条链路却看起来正常」的进程。
            // 先逆序清理已经跑起来的阶段，再中止（不留半装配状态）
            logger.error("应用装配失败，已中止启动：\(error)")
            composition.teardown(in: environment)
            preconditionFailure("应用装配失败：\(error)")
        }
        guard let manager = menuBarManager else {
            let message = "应用装配失败：菜单栏阶段未产出 MenuBarManager"
            logger.error(message)
            preconditionFailure(message)
        }
        logger.info("AppCoordinator 启动完成")
        return manager
    }

    /// 应用退出前清理
    ///
    /// 顺序不再手写：装配器按启动顺序逆序调用各阶段的 teardown（改造前是手写逆序）。
    public func stop() {
        if let compositionHandle {
            compositionHandle.teardown(in: AppEnvironment(coordinator: self))
        }
        compositionHandle = nil
        logger.info("AppCoordinator 已关闭")
    }
}