import Foundation

// MARK: - 系统指标监控服务

/// 系统指标监控服务 — CPU / GPU / 内存 / 磁盘 / 温度的统一采样入口
///
/// 实现约定：
/// - snapshot 由实现方在后台采集完成后回写，未完成首帧采样前为 nil；
/// - poll() 只负责触发一次采样，是否异步由实现决定，不阻塞调用方；
/// - 单项采集失败只影响该字段（nil），不得抛出错误或中断其余指标。
public protocol SystemMonitoringService: AnyObject {
    /// 最近一次完成的采样快照；首帧采样完成前为 nil
    var snapshot: SystemMetricsSnapshot? { get }

    /// 触发一次采样
    func poll()
}
