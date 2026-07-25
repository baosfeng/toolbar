import Foundation
import OSLog

// MARK: - OSLog 日志实现

/// 基于 os_log 的日志服务实现
///
/// 使用统一的 OSLog subsystem，支持日志级别过滤。
/// 生产环境默认只记录 info 及以上级别。
public final class OSLogLogger: LoggingService {
    private let osLog: OSLog
    private let minLevel: LogLevel

    /// 默认子系统
    public static let defaultSubsystem = "com.networkmonitor"

    /// 初始化
    /// - Parameters:
    ///   - subsystem: OSLog subsystem 标识
    ///   - category: 日志分类
    ///   - minLevel: 最低记录级别
    public init(subsystem: String = defaultSubsystem, category: String = "General",
                minLevel: LogLevel = .debug) {
        self.osLog = OSLog(subsystem: subsystem, category: category)
        self.minLevel = minLevel
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard shouldLog(level) else { return }

        let osLogType: OSLogType
        switch level {
        case .debug:   osLogType = .debug
        case .info:    osLogType = .info
        case .warning: osLogType = .default
        case .error:   osLogType = .error
        }

        os_log(osLogType, log: osLog, "%{public}@", message)
    }

    /// 判断当前级别是否需要记录
    private func shouldLog(_ level: LogLevel) -> Bool {
        let order: [LogLevel: Int] = [.debug: 0, .info: 1, .warning: 2, .error: 3]
        return (order[level] ?? 0) >= (order[minLevel] ?? 0)
    }
}

// MARK: - 控制台日志实现（测试用）

/// 控制台日志实现 — 直接 `print` 输出，适合开发/测试环境
public final class ConsoleLogger: LoggingService {
    private let minLevel: LogLevel
    private let dateFormatter: DateFormatter

    public init(minLevel: LogLevel = .debug) {
        self.minLevel = minLevel
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    public func log(_ level: LogLevel, _ message: String) {
        let order: [LogLevel: Int] = [.debug: 0, .info: 1, .warning: 2, .error: 3]
        guard (order[level] ?? 0) >= (order[minLevel] ?? 0) else { return }

        let timestamp = dateFormatter.string(from: Date())
        let prefix: String
        switch level {
        case .debug:   prefix = "🔍"
        case .info:    prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error:   prefix = "❌"
        }
        print("[\(timestamp)] \(prefix) [\(level.rawValue)] \(message)")
    }
}
