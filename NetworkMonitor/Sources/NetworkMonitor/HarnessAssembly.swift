import Foundation
import NetworkMonitorCore

// MARK: - Token 统计链路装配

/// DSH Token 统计链路装配 —— 从 AppCoordinator 扩展里搬出（族行数只允许变小）
///
/// 装配内容是「解析会话目录 → 建扫描器 → 建门面服务 → 接状态回调」，
/// 不依赖 AppCoordinator 的任何状态，因此独立成纯工厂即可复用（设置页换目录也走同一套）。
enum HarnessAssembly {

    /// 造一个门面服务：目录来源 = 显式偏好 > DSH_HOME > ~/.dsh/sessions
    ///
    /// - Parameter onStateChange: 状态回调（组合根用来发 AppEvents 刷新面板）
    static func makeService(database: any HarnessTokenRepository,
                            storage: any KeyValueStorage = AppContext.shared.storage,
                            logger: LoggingService = AppContext.shared.logger,
                            onStateChange: (@Sendable () -> Void)? = { AppEvents.postHarnessUsageChanged() })
        -> any HarnessUsageServicing {
        let resolution = HarnessSourceDirectory.resolve(storage: storage)
        let scanner = HarnessSessionScanner(resolution: resolution,
                                            streamer: HarnessZstdLineStreamer(logger: logger))
        let service = HarnessUsageService(scanner: scanner, store: database, logger: logger)
        if let onStateChange {
            service.setStateObserver { _ in onStateChange() }
        }
        return service
    }
}
