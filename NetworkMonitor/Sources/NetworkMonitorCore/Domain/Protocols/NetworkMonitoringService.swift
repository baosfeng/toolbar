import Foundation

// MARK: - 网络监控服务

/// 网络速度监控服务 — 实时网速和累计流量
public protocol NetworkMonitoringService: AnyObject {
    /// 当前下载速度（字节/秒）
    var downloadSpeed: Double { get }
    /// 当前上传速度（字节/秒）
    var uploadSpeed: Double { get }
    /// 累计接收字节
    var totalRx: UInt64 { get }
    /// 累计发送字节
    var totalTx: UInt64 { get }

    /// 轮询一次，更新速度值
    func poll()
}

// MARK: - 进程网络监控服务

/// 按进程网络使用监控
public protocol ProcessNetworkMonitoringService: AnyObject {
    /// 当前各进程网速列表
    var processSpeeds: [ProcessNetUsage] { get }

    /// 轮询一次，更新进程网速
    func poll()
}
