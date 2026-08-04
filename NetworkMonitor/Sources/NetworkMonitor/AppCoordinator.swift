import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器

/// 应用协调器 — 管理所有服务的生命周期和依赖注入
///
/// 职责：
/// - 初始化所有基础设施服务
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
    /// Token 用量查询
    private var tokenUsageProvider: (any TokenStatsService)!
    /// 每日流量追踪
    private var trafficTracker: (any TrafficTrackingService)!

    // MARK: - 日志

    public var logger: LoggingService = AppContext.shared.logger



    // MARK: - 初始化

    public init() {
        logger.info("AppCoordinator 初始化中...")
    }

    /// 启动所有服务
    func start() -> MenuBarManager {
        // 1. 数据库
        database = DatabaseManager()
        database.initialize()

        // 2. 网络监控
        let savedRx = UInt64(AppContext.shared.storage.integer(forKey: "totalRx"))
        let savedTx = UInt64(AppContext.shared.storage.integer(forKey: "totalTx"))
        networkMonitor = NetworkSpeedMonitor(totalRx: savedRx, totalTx: savedTx)

        // 3. Token 用量
        tokenUsageProvider = TokenUsageProvider(database: database)

        // 4. 流量追踪
        trafficTracker = TrafficTracker(monitor: networkMonitor)

        // 5. 创建 MenuBarManager（注入依赖）
        let manager = MenuBarManager(
            networkMonitor: networkMonitor,
            processMonitor: processMonitor,
            database: database,
            trafficTracker: trafficTracker,
            tokenUsageProvider: tokenUsageProvider
        )

        // 6. 启动定时轮询（由 MenuBarManager 的 setupTimer 完成）
        logger.info("AppCoordinator 启动完成")
        return manager
    }

    /// 应用退出前清理
    public func stop() {
        // 保存累计流量
        AppContext.shared.storage.set(Int(networkMonitor?.totalRx ?? 0), forKey: "totalRx")
        AppContext.shared.storage.set(Int(networkMonitor?.totalTx ?? 0), forKey: "totalTx")

        // 清理 Hook socket
        ReasonixHookMonitor.cleanupSocket()

        database?.close()
        logger.info("AppCoordinator 已关闭")
    }
}
