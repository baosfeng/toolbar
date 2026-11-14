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
            .general: { [weak self] in
                guard let self else { return Self.unavailable(.general) }
                return SettingsGeneralPane(
                    launchAtStartup: LaunchAtStartupService(logger: AppContext.shared.logger),
                    alertPreferences: BillingAlertPreferences(storage: AppContext.shared.storage),
                    notificationContext: self.settingsNotificationContext)
            },
            .appearance: {
                SettingsAppearancePane(logger: AppContext.shared.logger)
            },
            .providers: { [weak self] in
                guard let self else { return Self.unavailable(.providers) }
                return SettingsProvidersPane(monitor: billingMonitor,
                                             notificationContext: self.settingsNotificationContext)
            },
            .clipboard: { [weak self] in
                guard let self else { return Self.unavailable(.clipboard) }
                return SettingsClipboardPane(delegate: self,
                                             notificationContext: self.settingsNotificationContext,
                                             logger: self.logger)
            },
            .capture: { [weak self] in
                guard let self else { return Self.unavailable(.capture) }
                // 只读热键摘要来自 SnipController；未注册时给出可读兜底
                return SettingsCapturePane(hotKeyDelegate: self,
                                         hotKeySummary: { [weak self] in
                    self?.snipController?.hotKeySummary ?? "热键尚未注册"
                },
                                         notificationContext: self.settingsNotificationContext,
                                         logger: self.logger)
            },
            .transfer: { [weak self] in
                guard let self, let service = self.transferService else {
                    return Self.unavailable(.transfer,
                                             message: "互传服务未启动：端口被占用或未授予本地网络权限。")
                }
                return SettingsTransferPane(service: service,
                                            notificationContext: self.settingsNotificationContext,
                                            logger: self.logger)
            },
            .notifications: { [weak self] in
                guard let self else { return Self.unavailable(.notifications) }
                return SettingsNotificationPane(preferences: self.notificationPreferences,
                                               player: self.soundPlayer,
                                               library: self.soundLibrary,
                                               service: self.notificationService,
                                               logger: self.logger)
            },
            // 系统监控：偏好走 Core 的 SystemMonitorPreferences（与面板共用同一实现）
            .system: { SettingsSystemPane(preferences: SystemMonitorPreferences()) },
            .about: { SettingsAboutPane() },
        ]
        return SettingsWindow(factories: factories, logger: logger)
    }

    /// 通知事件行的共享依赖 — 各功能页注入同一份
    ///
    /// 四个依赖同源（同一份 `NotificationPreferences`）：事件配置在各页改都写同一把键，
    /// 所以「下沉」只换位置、不改读写路径，老用户的历史配置原样生效。
    var settingsNotificationContext: SettingsNotificationEventContext {
        SettingsNotificationEventContext(preferences: notificationPreferences,
                                         player: soundPlayer,
                                         library: soundLibrary,
                                         service: notificationService,
                                         logger: logger)
    }

    /// 依赖未就绪时的占位页
    private static func unavailable(_ section: SettingsSection,
                                    message: String = "该页依赖尚未就绪。") -> SettingsPaneView {
        SettingsUnavailablePane(section: section, message: message)
    }
}