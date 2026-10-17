import AppKit
import NetworkMonitorCore

// MARK: - Menu Bar Manager

/// 菜单栏 UI 总控制器 — 状态栏网速显示 + 下拉面板生命周期
///
/// 状态栏只显示 ↑↓ 网速（`StatusBarView`）；点击按钮展开 `MenuPanelController` 的
/// NSPopover 自定义面板（网络 / 剪贴板 / 系统三页），不再使用 NSMenu。
@MainActor
final class MenuBarManager: NSObject {

    private let statusItem: NSStatusItem
    private let monitor: any NetworkMonitoringService
    private let processMonitor: any ProcessNetworkMonitoringService
    private let panel: MenuPanelController
    private let logger: LoggingService
    private var timer: Timer?

    /// 剪贴板历史面板入口（由组合根装配）
    var onOpenClipboardHistory: (() -> Void)?
    /// 剪贴板设置窗入口（由组合根装配）
    var onOpenClipboardSettings: (() -> Void)?

    // MARK: - 初始化

    init(networkMonitor: any NetworkMonitoringService,
         processMonitor: any ProcessNetworkMonitoringService,
         trafficTracker: any TrafficTrackingService,
         clipboardRepository: any ClipboardRepository,
         paster: ClipboardPaster,
         logger: LoggingService = AppContext.shared.logger) {
        self.monitor = networkMonitor
        self.processMonitor = processMonitor
        self.logger = logger
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = MenuPanelController(networkMonitor: networkMonitor,
                                         processMonitor: processMonitor,
                                         trafficTracker: trafficTracker,
                                         repository: clipboardRepository,
                                         paster: paster,
                                         logger: logger)
        super.init()

        configureStatusItem()
        panel.onOpenClipboardHistory = { [weak self] in self?.onOpenClipboardHistory?() }
        panel.onOpenClipboardSettings = { [weak self] in self?.onOpenClipboardSettings?() }
        setupTimer()
    }

    // MARK: - 状态栏配置

    /// 状态栏按钮：左键点击切换面板（不挂 NSMenu，点击外部由 popover 的 transient 行为收起）
    private func configureStatusItem() {
        guard let button = statusItem.button else {
            logger.error("状态栏按钮不可用，面板无法唤起")
            return
        }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .noImage
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button.bounds, of: button)
    }

    // MARK: - 定时器

    private func setupTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 立即更新一次，避免启动后 1 秒空白
        update()
    }

    /// 每秒刷新：网速（状态栏）+ 进程采样 + 面板展开时的分层刷新
    @objc private func update() {
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let title = StatusBarView.attributedString(downSpeed: formatSpeedShort(downSpeed),
                                                   upSpeed: formatSpeedShort(upSpeed))
        // 仅内容变化时设置，避免每秒触发整条 Auto Layout 链布局
        if statusItem.button?.attributedTitle != title {
            statusItem.button?.attributedTitle = title
        }

        // 进程采样（内部 3 秒节流 + 后台队列执行，不阻塞主线程）
        processMonitor.poll()
        // 面板自身按 1 秒 / 5 秒分层刷新（收起时内部直接返回）
        panel.tick()
    }
}
