import Foundation
import NetworkMonitorCore

// MARK: - Token 自动监控装配

/// tokenStage 的后台自动监控部分 —— 从 `AppAssemblyStages+Features.swift` 拆出
///
/// 拆出的理由只有一条：Features 主文件已贴单文件 15 KiB 门禁，装配细节放这里不涨主文件。
/// 语义仍是「一个阶段一处装配」：tokenStage 只调这两个方法。
extension AppCoordinator {

    /// 建并启动自动监控调度器（屏幕活动监听单槽，调度器链式包一层）
    func startTokenAutoIndexScheduler(service: any HarnessUsageServicing) -> TokenAutoIndexScheduler {
        let scheduler = TokenAutoIndexScheduler(service: service,
                                                storage: AppContext.shared.storage,
                                                logger: logger)
        if let screenActivity {
            scheduler.bind(to: screenActivity)
        }
        scheduler.start()
        return scheduler
    }

    /// 停调度器并还原屏幕活动回调（teardown 用；幂等）
    func stopTokenAutoIndexScheduler() {
        guard let scheduler = tokenAutoIndexScheduler else { return }
        if let screenActivity {
            scheduler.unbind(screenActivity)
        }
        scheduler.stop()
        tokenAutoIndexScheduler = nil
    }
}
