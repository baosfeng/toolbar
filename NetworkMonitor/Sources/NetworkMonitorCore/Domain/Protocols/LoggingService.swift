import Foundation

// MARK: - 日志级别

/// 日志级别
public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

// MARK: - 日志服务

/// 日志服务协议 — 所有日志输出通过此接口，便于测试和切换实现
public protocol LoggingService: AnyObject, Sendable {
    func log(_ level: LogLevel, _ message: String)
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

// MARK: - 默认实现（空操作）

public extension LoggingService {
    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
}
