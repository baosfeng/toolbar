import Foundation

// MARK: - 事件监听服务

/// 系统事件监听服务 — 监听应用切换、屏幕、系统休眠等事件
public protocol EventMonitoringService: AnyObject {
    func start()
    func stop()
}
