import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏管理器（状态栏文本组装）

/// 状态栏指标行组装 —— 本文件只剩「取数 → 交给 UI 库 → 拼分隔符」
///
/// 从 `MenuBarManager.swift` 拆出（主文件接近单文件 15 KiB 上限）。
/// 17 项指标的渲染白名单、标签解析与单位分派已搬到 `NetworkMonitorUI` 的
/// `MenuBarStatusParts`（可被 TestRunner 直接断言）；这里只负责把服务里的数据
/// 装成一份 `MenuBarStatusContext`，再按偏好顺序取片段。
extension MenuBarManager {

    /// 组装当前状态栏文本片段
    ///
    /// - Parameters:
    ///   - enabled: 已启用的指标集合
    ///   - order: 上屏顺序；nil = 读当前偏好（设置页改顺序后由 `AppEvents.menuBarDisplayChanged` 触发重渲染）
    ///   - snapshot: 最近一帧系统快照（未装配系统监控时为 nil）
    ///   - todayTraffic: 今日上下行字节总量
    ///   - weekTraffic: 近 7 日流量总量（本周口径）
    ///   - tokenTotals: Token 汇总（未装配 DSH 索引时为 nil）
    /// - Returns: 至少一段（全部关闭时回落下载速度，避免状态栏空白）
    func makeStatusParts(enabled: Set<MenuBarMetric>,
                         order: [MenuBarMetric]? = nil,
                         snapshot: SystemMetricsSnapshot?,
                         todayTraffic: UInt64,
                         weekTraffic: UInt64,
                         tokenTotals: HarnessUsageTotals?) -> [String] {
        let context = MenuBarStatusContext(downSpeed: max(monitor.downloadSpeed, 0),
                                           upSpeed: max(monitor.uploadSpeed, 0),
                                           snapshot: snapshot,
                                           todayTraffic: todayTraffic,
                                           weekTraffic: weekTraffic,
                                           tokenTotals: tokenTotals,
                                           unitStyle: MenuBarDisplayLogic.unitStyle(
                                               fromRawValue: displayPreferences.unitStyle.rawValue),
                                           numberUnitStyle: numberUnitPreferences.style,
                                           labelStyle: displayPreferences.labelStyle,
                                           customLabels: displayPreferences.customLabels)
        return MenuBarStatusParts.make(enabled: enabled,
                                       order: order ?? displayPreferences.metricOrder,
                                       context: context)
    }
}
