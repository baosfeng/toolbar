import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureBilling
import NetworkMonitorFeatureClipboard
import NetworkMonitorUI

// MARK: - 装配阶段（额度 / 设置 / 菜单栏 / 收尾）

/// 装配阶段执行体（后半）—— 前半见 `AppAssemblyStages.swift`
///
/// 拆两文件只为守住单文件门禁（≤500 行 / 15 KiB）；阶段本身仍是一处声明、
/// 一处执行体，顺序由 `AppAssemblyPlan` 的 requires 拓扑排序决定。
extension AppCoordinator {

    // MARK: - 额度与设置

    /// 6. 额度页链路（provider 类型工厂 + 实例列表 + 凭据存储 + 状态管理器）
    ///
    /// 同一 provider 类型可起多个实例：默认实例 id == kindID（沿用旧凭据键，升级零迁移），
    /// 命名实例（如 cursor::work）各自一份凭据与开关。具体 provider 类只在这里 new。
    var billingStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.billing,
                      requires: [AppAssemblyPlan.notifications],
                      run: { env in
                          let coordinator = env.coordinator
                          let billingLogger = coordinator.logger
                          // 九家 provider 共用组合根这一份传输层（连接池与超时配置只有一份）
                          let billingTransport = coordinator.httpTransport
                          let billingKinds: [(kindID: String, title: String, make: @MainActor () -> any BillingProvider)] = [
                              ("ollama", "Ollama", { OllamaBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              ("open-design", "Open Design", { OpenDesignBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              ("opencode-go", "OpenCode Go", { OpencodeGoBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              // 订阅额度三家：均为非公开端点（可能失效），失败只回报错误、保留上次成功数据
                              ("claude", "Claude", { ClaudeBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              ("codex", "Codex", { CodexBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              ("cursor", "Cursor", { CursorBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              // 官方文档化端点三家，只出余额卡
                              ("deepseek", "DeepSeek", { DeepSeekBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              ("openrouter", "OpenRouter", { OpenRouterBillingProvider(transport: billingTransport, logger: billingLogger) }),
                              ("moonshot", "Moonshot / Kimi", { MoonshotBillingProvider(transport: billingTransport, logger: billingLogger) }),
                          ]
                          let billingInstanceStore = BillingInstanceStore()
                          let billingInstances = billingInstanceStore.ensureDefaults(
                              kinds: billingKinds.map { BillingInstanceKindSeed(kindID: $0.kindID, title: $0.title) })
                          let billingRegistry = BillingProviderRegistry()
                          for instance in billingInstances {
                              guard let kind = billingKinds.first(where: { $0.kindID == instance.kindID }) else { continue }
                              billingRegistry.register(BillingProviderInstance(base: kind.make(), instance: instance),
                                                       instance: instance)
                          }
                          // 环境变量回退键按实例解析（解析链唯一实现在 BillingProviderInstance.environmentCredentialKey）
                          let billingCredentials = PreferencesBillingCredentialStore(
                              environmentKeyResolver: { billingRegistry.provider(id: $0)?.environmentCredentialKey
                                  ?? BillingInstanceID.environmentKey(forInstanceID: $0) })
                          // 旧明文迁移：按注册表全量走一遍，不等用户点开某个 provider
                          billingCredentials.migrateLegacyPlaintext(for: billingRegistry.all.map(\.id))
                          // 额度提醒：应用启动时请求通知权限；通知出口统一注入 NotificationServicing
                          guard let notifications = coordinator.notificationService,
                                let soundPlayer = coordinator.soundPlayer else {
                              throw AppAssemblyError.missingService(stage: AppAssemblyPlan.billing,
                                                                    detail: "通知服务或音效播放器未装配")
                          }
                          let billingAlerts = BillingAlertService(storage: AppContext.shared.storage,
                                                                 notifications: notifications,
                                                                 soundPlayer: soundPlayer,
                                                                 logger: coordinator.logger)
                          billingAlerts.requestAuthorizationIfNeeded()
                          coordinator.billingMonitor = BillingMonitor(registry: billingRegistry,
                                                                      credentialStore: billingCredentials,
                                                                      alertService: billingAlerts,
                                                                      instances: billingInstanceStore,
                                                                      providerFactory: { kindID in
                                                                          billingKinds.first { $0.kindID == kindID }?.make()
                                                                      },
                                                                      logger: coordinator.logger)
                      })
    }

    /// 6c. 更新检查（设置页「关于」的数据源；启动 5 秒后自动查一次，24 小时限频）
    var updateCheckStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.updateCheck,
                      run: { env in env.coordinator.updateCheck = env.coordinator.makeUpdateCheckService() })
    }

    /// 6d. 统一设置窗口（十一个分类页；额度页直接用上一步的 billingMonitor）
    var settingsStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.settings,
                      requires: [AppAssemblyPlan.billing, AppAssemblyPlan.updateCheck],
                      run: { env in
                          guard let billingMonitor = env.coordinator.billingMonitor else {
                              throw AppAssemblyError.missingService(stage: AppAssemblyPlan.settings,
                                                                    detail: "额度状态管理器未装配")
                          }
                          env.coordinator.settingsWindow = env.coordinator.makeSettingsWindow(billingMonitor: billingMonitor)
                      })
    }

    /// 6e. 锁屏 / 休眠期间暂停额度后台轮询，解锁后立即刷新一次
    ///
    /// 【必须强持有】监听器只被局部变量引用时，EOF 后即释放；而通知中心只持闭包，
    /// 闭包里的 [weak self] 从此恒为 nil —— 额度刷新再也不会暂停 / 恢复，且无声无息
    /// （现象：额度页停在旧数据、时间戳不动、进程无对外连接）。故存成协调器属性。
    var screenActivityStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.screenActivity,
                      requires: [AppAssemblyPlan.billing],
                      run: { env in
                          let coordinator = env.coordinator
                          let monitor = coordinator.billingMonitor
                          let screenActivity = ScreenActivityMonitor(logger: coordinator.logger)
                          screenActivity.onChange = { [weak monitor] active in
                              if active {
                                  monitor?.resume()
                              } else {
                                  monitor?.pause()
                              }
                          }
                          screenActivity.start()
                          coordinator.screenActivity = screenActivity
                      },
                      teardown: { env in
                          env.coordinator.screenActivity?.stop()
                          env.coordinator.screenActivity = nil
                      })
    }

    /// 6f. Token 统计链路（多来源索引 + 后台自动监控）
    ///
    /// 调度器装配见 AppTokenAutoIndexStage.swift。
    var tokenStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.token,
                      requires: [AppAssemblyPlan.database, AppAssemblyPlan.screenActivity],
                      run: { env in
                          guard let database = env.coordinator.databaseManager else {
                              throw AppAssemblyError.missingService(stage: AppAssemblyPlan.token,
                                                                    detail: "数据库未装配")
                          }
                          let service = HarnessAssembly.makeService(database: database)
                          env.coordinator.harnessUsageService = service
                          env.coordinator.tokenAutoIndexScheduler =
                              env.coordinator.startTokenAutoIndexScheduler(service: service)
                      },
                      teardown: { env in env.coordinator.stopTokenAutoIndexScheduler() })
    }

    /// 6g. 系统监控链路（采样驱动见 MenuBarManager+Sampling）
    var systemMonitorStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.systemMonitor,
                      run: { env in
                          let context = env.coordinator.makeSystemMonitor()
                          env.coordinator.menuBarSystemContext = context
                          env.coordinator.systemMonitor = context.monitor
                      })
    }

    // MARK: - 菜单栏与收尾

    /// 7. 创建 MenuBarManager（注入依赖 + 面板所需仓储与粘贴器）
    var menuBarStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.menuBar,
                      requires: [AppAssemblyPlan.database, AppAssemblyPlan.network, AppAssemblyPlan.traffic,
                                 AppAssemblyPlan.clipboard, AppAssemblyPlan.notifications, AppAssemblyPlan.transfer,
                                 AppAssemblyPlan.billing, AppAssemblyPlan.token, AppAssemblyPlan.systemMonitor],
                      run: { env in
                          let coordinator = env.coordinator
                          guard let database = coordinator.database,
                                let clipboardWatcher = coordinator.clipboardWatcher,
                                let clipboardPaster = coordinator.clipboardPaster,
                                let systemContext = coordinator.menuBarSystemContext else {
                              throw AppAssemblyError.missingService(stage: AppAssemblyPlan.menuBar,
                                                                    detail: "数据库 / 剪贴板采集 / 粘贴器 / 系统监控上下文未装配")
                          }
                          let manager = MenuBarManager(
                              networkMonitor: coordinator.networkMonitor,
                              processMonitor: coordinator.processMonitor,
                              trafficTracker: coordinator.trafficTracker,
                              clipboardRepository: database,
                              captureService: clipboardWatcher,
                              paster: clipboardPaster,
                              transferController: coordinator.transferController,
                              billingMonitor: coordinator.billingMonitor,
                              harnessUsage: coordinator.harnessUsageService,
                              systemMonitor: systemContext.monitor,
                              systemPreferences: systemContext.preferences
                          )
                          // 面板打开前先重读权限：页脚与设置页读同一份快照，授权后不必重启
                          manager.onOpenClipboardHistory = { [weak coordinator] in coordinator?.toggleClipboardPanel() }
                          manager.onOpenSettings = { [weak coordinator] section in
                              coordinator?.settingsWindow?.show(section: section)
                          }
                          coordinator.menuBarManager = manager
                      })
    }

    /// 8. 累计流量定期落盘（崩溃 / 强杀时也能保住当日基准）
    var trafficPersistenceStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.trafficPersistence,
                      requires: [AppAssemblyPlan.network],
                      run: { env in env.coordinator.startTrafficPersistence() },
                      teardown: { env in
                          env.coordinator.trafficPersistenceTimer?.invalidate()
                          env.coordinator.trafficPersistenceTimer = nil
                          env.coordinator.persistTrafficTotals()
                      })
    }

    /// 8b. 更新检查：启动 5 秒后自动查一次（受 24 小时限频）
    var autoUpdateCheckStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.autoUpdateCheck,
                      requires: [AppAssemblyPlan.updateCheck],
                      run: { env in env.coordinator.scheduleAutoUpdateCheck() })
    }

    /// 9. 启动清理：先按容量上限清一次，再孤儿清扫
    var launchCleanupStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.launchCleanup,
                      requires: [AppAssemblyPlan.database, AppAssemblyPlan.clipboard],
                      run: { env in
                          let coordinator = env.coordinator
                          guard let database = coordinator.database,
                                let preferences = coordinator.clipboardPreferences else {
                              throw AppAssemblyError.missingService(stage: AppAssemblyPlan.launchCleanup,
                                                                    detail: "数据库或剪贴板偏好未装配")
                          }
                          ClipboardImageGC.sweepOrphansAfterLaunch(repository: database,
                                                                   maxBytes: preferences.maxBytes,
                                                                   logger: coordinator.logger)
                      })
    }

}