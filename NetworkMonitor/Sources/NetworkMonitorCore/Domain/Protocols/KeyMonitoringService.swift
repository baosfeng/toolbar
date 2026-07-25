import Foundation

// MARK: - 击键监控服务

/// 击键监控服务 — 监听键盘事件，仅计数不记录内容
public protocol KeyMonitoringService: AnyObject {
    /// 启动监听，返回是否成功（可能因权限不足失败）
    @discardableResult
    func start() -> Bool
    /// 停止监听
    func stop()
}
