import Foundation

// MARK: - Hook 事件服务

/// Reasonix Hook 事件监听服务
public protocol HookEventService: AnyObject, Sendable {
    /// 启动 UDS 监听器
    func start()
    /// 停止 UDS 监听器
    func stop()
    /// 清理 socket 文件
    static func cleanupSocket()
}
