import Foundation

// MARK: - 系统采样服务

/// 系统采样服务 — 定时采集 CPU、内存、网络数据
public protocol SystemSamplingService: AnyObject, Sendable {
    /// 启动定时采样
    func start()
    /// 停止定时采样
    func stop()
    /// 立即执行一次采样
    func sample()
}
