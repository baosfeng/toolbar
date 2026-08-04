import Foundation

// MARK: - 每日流量追踪服务

/// 每日流量追踪服务协议 — 今日累计流量与近 7 日日志
///
/// 抽象 `TrafficTracker`，使 UI 层依赖协议而非具体实现，便于替换与测试。
public protocol TrafficTrackingService: AnyObject {
    /// 今日流量（下行）
    var todayRx: UInt64 { get }
    /// 今日流量（上行）
    var todayTx: UInt64 { get }
    /// 近 7 日每日流量明细（日期降序：今天在最前）
    var weekEntries: [(label: String, rx: UInt64, tx: UInt64)] { get }

    /// 加载或初始化每日流量起点
    func load()
    /// 检查日期变更，切换并保存每日日志
    func update()
}
