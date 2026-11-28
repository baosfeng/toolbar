import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - CLI 页面命令接收端

/// 运行中的 app 监听 CLI 页面命令，收到目标后把对应页面打开
///
/// 与旧探针通道的区别（这是本文件存在的全部理由）：
/// - 探针：带 `NM_*` 环境变量另起一个进程 → 离屏渲染 → `exit(0)`。用户正在用的那个进程帮不上忙，
///   取证必须先把 app 杀掉再重开，跑完还少一个实例。
/// - 本通道：对**已在运行**的进程投一条分布式通知，打开页面后原地返回；不读环境变量、不退出、不改偏好。
///
/// 截图由 nmcli 侧完成（CGWindowList 找窗口 + screencapture），app 只负责「把页面打开到位」。
@MainActor
final class CLIPageBridge {

    static let shared = CLIPageBridge()

    private var observer: NSObjectProtocol?
    /// 弱引用：桥的生命周期跟进程一致，但不应把协调器钉住
    private weak var coordinator: AppCoordinator?

    private init() {}

    /// 装配（组合根启动末尾调用一次；重复调用无副作用）
    func start(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(CLIPageChannel.commandName),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[CLIPageChannel.keyTarget] as? String
            let request = notification.userInfo?[CLIPageChannel.keyRequest] as? String
            Task { @MainActor in self?.handle(rawTarget: raw, request: request) }
        }
    }

    /// 处理一条命令（未知目标静默忽略：CLI 侧会自己超时报错，app 不弹窗打扰用户）
    private func handle(rawTarget: String?, request: String?) {
        guard let coordinator else { return }
        guard let target = CLIPageTarget.parse(rawTarget ?? "current") else { return }
        var windowNumber = 0
        switch target {
        case .current:
            windowNumber = coordinator.menuBarManager?.panel.popover.contentViewController?.view.window?.windowNumber ?? 0
        case .clipboard:
            coordinator.clipboardPanel?.show()
            // 剪贴板面板的 window 是控制器私有持有，这里按类型在 app 窗口表里找，
            // 不给控制器新增只读属性（同族行数门禁只允许变小，不为一个取证入口增长生产类）
            windowNumber = NSApp.windows.first { $0 is ClipboardPanel && $0.isVisible }?.windowNumber ?? 0
        case .menu(let tabID):
            coordinator.menuBarManager?.showPanelForCLIPage(tabID: tabID)
            windowNumber = coordinator.menuBarManager?.panel.popover.contentViewController?.view.window?.windowNumber ?? 0
        case .settings(let sectionID):
            let section = sectionID.flatMap { SettingsSection(rawValue: $0) }
            coordinator.settingsWindow?.show(section: section)
            windowNumber = coordinator.settingsWindow?.window.windowNumber ?? 0
        }
        postReceipt(target: target, request: request, windowNumber: windowNumber)
        coordinator.logger.debug("CLI 页面命令：已打开 \(target.rawValue)（window=\(windowNumber)）")
    }

    /// 回执 —— 带上目标窗口号，调用方据此截图，不必靠窗口尺寸猜是哪个页面
    private func postReceipt(target: CLIPageTarget, request: String?, windowNumber: Int) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(CLIPageChannel.receiptName),
            object: nil,
            userInfo: [
                CLIPageChannel.keyTarget: target.rawValue,
                CLIPageChannel.keyRequest: request ?? "",
                CLIPageChannel.keyWindowNumber: windowNumber,
            ],
            deliverImmediately: true
        )
    }
}
