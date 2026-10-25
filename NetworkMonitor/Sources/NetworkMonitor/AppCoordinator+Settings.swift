import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（统一设置窗口装配）

/// 设置窗口装配 — 六个分类页的工厂在这里收口
///
/// 工厂用 `[weak self]` 捕获：设置窗口生命周期与协调器同长，强捕获会形成
/// `AppCoordinator → SettingsWindow → 工厂闭包 → AppCoordinator` 的环。
/// 依赖确实缺位时（如互传服务未启动）返回占位页，而不是让设置窗口打不开。
extension AppCoordinator {

    /// 装配统一设置窗口
    ///
    /// - Parameter billingMonitor: 计费状态管理器（额度页开关与凭据编辑直接用它的 API）
    func makeSettingsWindow(billingMonitor: BillingMonitor) -> SettingsWindow {
        let factories: [SettingsSection: SettingsWindow.PaneFactory] = [
            .general: {
                SettingsGeneralPane(
                    launchAtStartup: LaunchAtStartupService(logger: AppContext.shared.logger),
                    alertPreferences: BillingAlertPreferences(storage: AppContext.shared.storage))
            },
            .providers: {
                SettingsProvidersPane(monitor: billingMonitor)
            },
            .clipboard: { [weak self] in
                guard let self else { return Self.unavailable(.clipboard) }
                return SettingsClipboardPane(delegate: self, logger: self.logger)
            },
            .capture: { [weak self] in
                guard let self else { return Self.unavailable(.capture) }
                // 只读热键摘要来自 SnipController；未注册时给出可读兜底
                return SettingsCapturePane(hotKeySummary: { [weak self] in
                    self?.snipController?.hotKeySummary ?? "热键尚未注册"
                }, logger: self.logger)
            },
            .transfer: { [weak self] in
                guard let self, let service = self.transferService else {
                    return Self.unavailable(.transfer,
                                             message: "互传服务未启动：端口被占用或未授予本地网络权限。")
                }
                return SettingsTransferPane(service: service, logger: self.logger)
            },
            .about: { SettingsAboutPane() },
        ]
        return SettingsWindow(factories: factories, logger: logger)
    }

    /// 依赖未就绪时的占位页
    private static func unavailable(_ section: SettingsSection,
                                    message: String = "该页依赖尚未就绪。") -> SettingsPaneView {
        SettingsUnavailablePane(section: section, message: message)
    }
}