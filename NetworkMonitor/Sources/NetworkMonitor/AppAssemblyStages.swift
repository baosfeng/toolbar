import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 装配阶段（基础设施与功能链路）

/// 装配阶段的**执行体** —— 顺序与依赖声明在 `AppAssemblyPlan`（纯值，TestRunner 可断言）
///
/// 改造前这些代码是 `AppCoordinator.start()` 里一长串顺序语句，依赖只靠代码位置与注释；
/// 现在每一段搬进一个 `AssembleStage` 的 run 闭包，内部逻辑与注入顺序原样保留，
/// 执行顺序由装配器按 `requires` 拓扑排序给出（结果与改造前逐项相同）。
/// 后续十个阶段见 `AppAssemblyStages+Features.swift`（拆文件只为守住单文件门禁）。
extension AppCoordinator {

    /// 全部装配阶段（顺序 = 声明序；拓扑排序后与改造前手写顺序逐项一致）
    ///
    /// 各阶段属性放宽为 internal：装配阶段分在两个扩展文件里（守住单文件门禁），
    /// 跨文件引用需要 internal；除此之外没有别的调用方。
    var assembleStages: [AssembleStage] {
        [databaseStage, networkStage, trafficStage, notificationsStage,
         clipboardStage, snipStage, permissionsStage, transferStage,
         billingStage, updateCheckStage, settingsStage, screenActivityStage,
         tokenStage, systemMonitorStage, menuBarStage,
         trafficPersistenceStage, autoUpdateCheckStage, launchCleanupStage]
    }

    // MARK: - 基础设施与网络

    /// 1. 数据库（同一实例满足 DatabaseService 与 ClipboardRepository）
    var databaseStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.database,
                      run: { env in
                          let manager = DatabaseManager()
                          manager.initialize()
                          env.coordinator.database = manager
                          env.coordinator.databaseManager = manager
                      },
                      teardown: { env in env.coordinator.database?.close() })
    }

    /// 2. 网络监控（累计字节从 storage 起步）
    var networkStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.network,
                      run: { env in
                          let savedRx = UInt64(AppContext.shared.storage.integer(forKey: "totalRx"))
                          let savedTx = UInt64(AppContext.shared.storage.integer(forKey: "totalTx"))
                          env.coordinator.networkMonitor = NetworkSpeedMonitor(totalRx: savedRx, totalTx: savedTx)
                      })
    }

    /// 3. 流量追踪（依赖网络监控）
    var trafficStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.traffic,
                      requires: [AppAssemblyPlan.network],
                      run: { env in
                          env.coordinator.trafficTracker = TrafficTracker(monitor: env.coordinator.networkMonitor)
                      })
    }

    /// 3b. 通知与音效（必须早于剪贴板与额度，它们都从这里取实例）
    var notificationsStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.notifications,
                      run: { env in env.coordinator.setupNotificationAndFeedback() })
    }

    // MARK: - 功能链路

    /// 4. 剪贴板历史链路（依赖数据库 + 通知与音效）
    var clipboardStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.clipboard,
                      requires: [AppAssemblyPlan.database, AppAssemblyPlan.notifications],
                      run: { env in
                          guard let database = env.coordinator.database else {
                              throw AppAssemblyError.missingService(stage: AppAssemblyPlan.clipboard,
                                                                    detail: "数据库未装配")
                          }
                          env.coordinator.setupClipboard(database: database)
                      },
                      teardown: { env in
                          env.coordinator.clipboardWatcher?.stop()
                          env.coordinator.clipboardStack?.stop()
                          env.coordinator.clipboardOCR?.cancelAll()
                          env.coordinator.globalHotKey?.unregister()
                      })
    }

    /// 4b. 截图 / 贴图链路
    var snipStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.snip,
                      run: { env in env.coordinator.setupSnip() })
    }

    /// 4c. 系统权限链路（必须在截图之后：屏幕录制状态读捕获服务 preflight）
    var permissionsStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.permissions,
                      requires: [AppAssemblyPlan.snip, AppAssemblyPlan.notifications],
                      run: { env in env.coordinator.setupPermissions() })
    }

    /// 5. 局域网互传（发现层 + 传输服务 + 面板控制器）
    var transferStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.transfer,
                      requires: [AppAssemblyPlan.notifications],
                      run: { env in _ = env.coordinator.makeTransferController() },
                      teardown: { env in env.coordinator.transferController?.stop() })
    }
}