import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - 应用协调器（统一设置窗口装配）

/// 设置窗口装配 — 十一个分类的造页闭包在这里逐条注册
///
/// 闭包用 `[weak self]` 捕获：设置窗口生命周期与协调器同长，强捕获会形成
/// `AppCoordinator → SettingsWindow → 注册表 → 闭包 → AppCoordinator` 的环。
/// 依赖确实缺位时（如互传服务未启动）返回占位页，而不是让设置窗口打不开。
extension AppCoordinator {

    /// 装配统一设置窗口
    ///
    /// - Parameter billingMonitor: 计费状态管理器（额度页开关与凭据编辑直接用它的 API）
    func makeSettingsWindow(billingMonitor: BillingMonitor) -> SettingsWindow {
        let modules = SettingsModuleRegistry()
        registerSettingsModules(into: modules, billingMonitor: billingMonitor)
        return SettingsWindow(modules: modules, logger: logger)
    }

    /// 逐条注册十一个分类（新增分类 = 加一条 register，不动任何既有条目）
    /// 与改造前那张工厂字典逐项等价：顺序由 `SettingsSectionCatalog` 决定。
    private func registerSettingsModules(into modules: SettingsModuleRegistry,
                                         billingMonitor: BillingMonitor) {
        modules.register(SettingsModule(section: .general) { [weak self] in
            guard let self else { return Self.unavailable(.general) }
            return SettingsGeneralPane(
                launchAtStartup: LaunchAtStartupService(logger: AppContext.shared.logger),
                alertPreferences: BillingAlertPreferences(storage: AppContext.shared.storage),
                smoothScrollStateText: { [weak self] in
                    self?.scrollSmoothingStateText ?? "未启用"
                },
                onSmoothScrollChange: { [weak self] in
                    self?.applyScrollSmoothingPreferences()
                },
                notificationContext: self.settingsNotificationContext)
        })
        modules.register(SettingsModule(section: .appearance) {
            SettingsAppearancePane(logger: AppContext.shared.logger)
        })
        modules.register(SettingsModule(section: .providers) { [weak self] in
            guard let self else { return Self.unavailable(.providers) }
            return SettingsProvidersPane(monitor: billingMonitor,
                                         notificationContext: self.settingsNotificationContext)
        })
        modules.register(SettingsModule(section: .clipboard) { [weak self] in
            guard let self, let permissions = self.permissionChain else {
                return Self.unavailable(.clipboard, message: "系统权限状态尚未就绪，请稍后重开设置。")
            }
            return SettingsClipboardPane(delegate: self, permissions: permissions,
                                         notificationContext: self.settingsNotificationContext,
                                         logger: self.logger)
        })
        modules.register(SettingsModule(section: .capture) { [weak self] in
            self?.makeCapturePane() ?? Self.unavailable(.capture)
        })
        modules.register(SettingsModule(section: .transfer) { [weak self] in
            guard let self, let service = self.transferService else {
                return Self.unavailable(.transfer,
                                        message: "互传服务未启动：端口被占用或未授予本地网络权限。")
            }
            return SettingsTransferPane(service: service,
                                        notificationContext: self.settingsNotificationContext,
                                        logger: self.logger)
        })
        modules.register(SettingsModule(section: .notifications) { [weak self] in
            self?.makeNotificationPane() ?? Self.unavailable(.notifications)
        })
        // 系统权限：五类授权的唯一集中页（其余功能页只留就地简版）
        modules.register(SettingsModule(section: .permissions) { [weak self] in
            guard let self else { return Self.unavailable(.permissions) }
            return self.makePermissionPane()
        })
        // Token 用量：数据源目录 / zstd 诊断 + 索引维护（重扫 / 清理）
        modules.register(SettingsModule(section: .token) { [weak self] in
            guard let self, let harness = self.harnessUsageService,
                  let store = self.database as? any HarnessTokenRepository else {
                return Self.unavailable(.token, message: "Token 统计服务尚未就绪。")
            }
            return SettingsTokenPane(controller: SettingsTokenController(
                harness: harness, store: store, logger: self.logger))
        })
        // 系统监控：偏好走 Core 的 SystemMonitorPreferences（与面板共用同一实现）
        modules.register(SettingsModule(section: .system) {
            SettingsSystemPane(preferences: SystemMonitorPreferences())
        })
        modules.register(SettingsModule(section: .about) { [weak self] in
            guard let self, let updateCheck = self.updateCheck else {
                return Self.unavailable(.about, message: "更新检查服务尚未就绪。")
            }
            return SettingsAboutPane(updateCheck: updateCheck, isCertificateSigned: self.permissionChain?.isCertificateSigned)
        })
    }

    /// 通知事件行的共享依赖 — 各功能页注入同一份
    /// 四个依赖同源（同一份 `NotificationPreferences`），事件配置在各页改都写同一把键。
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
