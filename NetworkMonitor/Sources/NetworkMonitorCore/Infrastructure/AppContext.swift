import Foundation

// MARK: - 应用上下文

/// 应用全局服务容器 — 集中管理共享基础设施的依赖注入
///
/// 使用方式：
/// ```swift
/// // App 启动时配置
/// AppContext.shared.configure(logger: OSLogLogger(...), storage: UserDefaultsStorage())
/// ```
public final class AppContext: @unchecked Sendable {
    /// 全局共享实例
    public static let shared = AppContext()

    /// 日志服务（默认使用 ConsoleLogger，生产环境可注入 OSLogLogger）
    public private(set) var logger: LoggingService = ConsoleLogger()

    /// 键值存储（默认使用 UserDefaults.standard）
    public private(set) var storage: KeyValueStorage = UserDefaultsStorage()

    private init() {}

    /// 配置全局服务
    /// - Parameters:
    ///   - logger: 日志服务实现（nil 保留当前值）
    ///   - storage: 键值存储实现（nil 保留当前值）
    public func configure(logger: LoggingService? = nil, storage: KeyValueStorage? = nil) {
        if let logger { self.logger = logger }
        if let storage { self.storage = storage }
    }
}
