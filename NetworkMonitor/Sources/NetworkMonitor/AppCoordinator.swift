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
    private var networkMonitor: (any NetworkMonitoringService)!
    /// 进程网络监控
    private let processMonitor: any ProcessNetworkMonitoringService = ProcessNetworkMonitor()
    /// 数据库
    private var database: (any AppDatabase)!
    /// 每日流量追踪
    private var trafficTracker: (any TrafficTrackingService)!

    // MARK: - 剪贴板历史

    /// 剪贴板偏好
    private var clipboardPreferences: ClipboardPreferences!
    /// 采集器（分支 A / 分支 B 是同一个实现的两种模式）
    private var clipboardWatcher: PasteboardWatcher!
    /// 粘贴器（写回剪贴板 + 合成 ⌘V）
    private var clipboardPaster: ClipboardPaster!
    /// Paste Stack 状态机
    private var clipboardStack: PasteStackController!
    /// 面板控制器
    private var clipboardPanel: ClipboardPanelController!
    /// 设置窗
    private var clipboardSettings: ClipboardSettingsWindow!
    /// 全局热键
    private var globalHotKey: GlobalHotKeyCenter!
    /// 局域网互传面板控制器
    private var transferController: TransferController?

    // MARK: - 日志

    public var logger: LoggingService = AppContext.shared.logger

    // MARK: - 初始化

    public init() {
        logger.info("AppCoordinator 初始化中...")
    }

#if DEBUG
    /// 快照钩子专用（仅 DEBUG）：暴露数据库以便渲染真实剪贴板条目
    var snapshotClipboardRepository: (any ClipboardRepository)? { database }
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

        // 5. 局域网互传（发现层 + 传输服务 + 面板控制器）
        let transfer = makeTransferController()

        // 6. 创建 MenuBarManager（注入依赖 + 面板所需仓储与粘贴器）
        let manager = MenuBarManager(
            networkMonitor: networkMonitor,
            processMonitor: processMonitor,
            trafficTracker: trafficTracker,
            clipboardRepository: databaseManager,
            paster: clipboardPaster,
            transferController: transfer
        )
        manager.onOpenClipboardHistory = { [weak self] in self?.clipboardPanel.toggle() }
        manager.onOpenClipboardSettings = { [weak self] in self?.clipboardSettings.show() }

        // 7. 启动定时轮询（由 MenuBarManager 的 setupTimer 完成）
        logger.info("AppCoordinator 启动完成")
        return manager
    }

    /// 应用退出前清理
    public func stop() {
        // 保存累计流量
        AppContext.shared.storage.set(Int(networkMonitor?.totalRx ?? 0), forKey: "totalRx")
        AppContext.shared.storage.set(Int(networkMonitor?.totalTx ?? 0), forKey: "totalTx")

        // 局域网互传
        transferController?.stop()

        // 剪贴板链路
        clipboardWatcher?.stop()
        clipboardStack?.stop()
        globalHotKey?.unregister()

        database?.close()
        logger.info("AppCoordinator 已关闭")
    }

    // MARK: - 局域网互传装配

    /// 装配传输服务：设备表 + 发现层 + HTTP 服务 + 面板控制器
    private func makeTransferController() -> TransferController {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let identity = LocalIdentity.makeDefault(port: Int(TransferProtocol.defaultPorts[0]),
                                                 appVersion: appVersion)
        let registry = DeviceRegistry()
        let configuration = TransferService.Configuration(
            receiveDirectory: TransferService.Configuration.defaultReceiveDirectory(),
            appVersion: appVersion)
        let preferences = TransferPreferences(storage: AppContext.shared.storage)
        let service = TransferService(identity: identity,
                                      registry: registry,
                                      configuration: configuration,
                                      preferences: preferences,
                                      logger: logger)
        let controller = TransferController(service: service, registry: registry,
                                            preferences: preferences, logger: logger)
        transferController = controller
        // 服务常驻：面板未打开也要能收发，启动在后台完成
        controller.start()
        return controller
    }

    // MARK: - 剪贴板历史装配

    /// 装配剪贴板链路：偏好 → 写回 → 粘贴 → 采集 → 栈 → 面板 → 设置 → 全局热键
    private func setupClipboard(database: any AppDatabase) {
        let preferences = ClipboardPreferences()
        clipboardPreferences = preferences

        let writer = PasteboardWriter()
        let paster = ClipboardPaster(writer: writer, preferences: preferences)
        clipboardPaster = paster

        let watcher = PasteboardWatcher(preferences: preferences)
        clipboardWatcher = watcher
        // 落库与事件发布由组合根在回调里完成（Core 采集器不触碰仓储）
        watcher.onCapture = { [weak self] draft in self?.persistClipboardDraft(draft) }
        watcher.onStateChange = { [weak self] state in self?.handleCaptureState(state) }
        watcher.start()

        let stack = PasteStackController(repository: database, writer: writer)
        clipboardStack = stack
        stack.start()

        clipboardPanel = ClipboardPanelController(repository: database,
                                                  captureService: watcher,
                                                  paster: paster,
                                                  stack: stack,
                                                  // ⌘, 复用设置窗既有打开路径
                                                  onRequestSettings: { [weak self] in self?.clipboardSettings.show() },
                                                  preferences: preferences)
        clipboardSettings = ClipboardSettingsWindow(preferences: preferences, delegate: self)

        globalHotKey = GlobalHotKeyCenter()
        registerClipboardHotKey(preferences.panelToggleHotKey, presentingAlert: true)
    }

    /// 采集回调：落库 + 广播 + 超限清理
    ///
    /// 死锁红线：仓储方法全部是串行队列 sync，必须在主线程调用；
    /// 禁止在 db.query(sql:handler:) 回调内或数据库串行队列上下文调用，否则立即死锁。
    private func persistClipboardDraft(_ draft: ClipboardDraft) {
        guard let repository = database else { return }
        guard repository.saveClipboardItem(draft) != nil else {
            logger.warning("剪贴板条目落库失败（数据库未就绪或内容无效）")
            return
        }
        AppEvents.postClipboardChanged()
        // 超限清理：条数超过上限或早于保留天数的非收藏项会被删除
        _ = repository.pruneClipboardItems(maxItems: clipboardPreferences.maxItems,
                                          retentionDays: clipboardPreferences.retentionDays)
    }

    /// 采集状态变化：权限被拒时明确告警（不静默）
    private func handleCaptureState(_ state: ClipboardCaptureState) {
        switch state {
        case .running:
            logger.info("剪贴板采集运行中")
        case .stopped:
            logger.info("剪贴板采集未运行（按需采集模式或已停止）")
        case .denied(let reason):
            logger.warning("剪贴板访问被拒绝（\(reason.rawValue)）：请到「系统设置 → 隐私与安全性」允许本应用访问剪贴板")
        }
    }

    /// 注册全局唤起热键；失败时不静默，引导用户去系统设置释放占用
    @discardableResult
    private func registerClipboardHotKey(_ combo: HotKeyCombo, presentingAlert: Bool) -> Bool {
        let result = globalHotKey.register(combo) { [weak self] in self?.clipboardPanel.toggle() }
        switch result {
        case .success:
            return true
        case .conflict, .failed:
            logger.error("剪贴板全局热键注册失败：\(combo.displayString)（可能被其他应用占用）")
            if presentingAlert { presentHotKeyConflictAlert(combo) }
            return false
        }
    }

    /// 热键冲突提示（延迟到启动完成后弹出，避免阻塞 App 启动）
    private func presentHotKeyConflictAlert(_ combo: HotKeyCombo) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let alert = NSAlert()
            alert.messageText = "快捷键 \(combo.displayString) 注册失败"
            alert.informativeText = "该组合键可能已被其他应用占用。请到「系统设置 → 键盘 → 键盘快捷键」释放占用后，在剪贴板设置中重新录制。"
            alert.addButton(withTitle: "打开剪贴板设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                self.clipboardSettings.show()
            }
        }
    }
}

// MARK: - 设置窗回调

extension AppCoordinator: ClipboardSettingsDelegate {

    /// 设置窗内重新录制快捷键：冲突时由设置窗标记冲突态，不再弹模态框
    func settingsDidChangeHotKey(_ combo: HotKeyCombo) -> Bool {
        registerClipboardHotKey(combo, presentingAlert: false)
    }

    /// 采集模式切换：按新模式重启采集器（分支 B 轮询 / 分支 A 按需）
    func settingsDidChangeCaptureMode() {
        clipboardWatcher.stop()
        clipboardWatcher.start()
        logger.info("剪贴板采集模式已切换为：\(clipboardPreferences.captureMode.label)")
    }

    func settingsDidChangeIgnoredApps() {
        logger.info("剪贴板忽略应用已更新，共 \(clipboardPreferences.ignoredBundleIDs.count) 项")
    }

    func settingsAccessibilityGranted() -> Bool {
        clipboardStack.refreshAccessibility()
    }

    func settingsDidRequestAccessibilityPermission() {
        clipboardStack.requestAccessibilityPermission()
    }

    func settingsDidRequestClipboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }
}
