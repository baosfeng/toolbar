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
    /// 逐指标的状态栏片段（带 metric）—— 自绘图标化渲染需要「哪一段属于哪一项」
    ///
    /// 与 makeStatusParts 共用同一份上下文与顺序口径，只是不提前拼成字符串。
    func makeStatusSegments(enabled: Set<MenuBarMetric>,
                            order: [MenuBarMetric]? = nil,
                            snapshot: SystemMetricsSnapshot?,
                            todayTraffic: UInt64,
                            weekTraffic: UInt64,
                            tokenTotals: HarnessUsageTotals?) -> [MenuBarStatusRenderer.Segment] {
        let context = makeStatusContext(snapshot: snapshot,
                                        todayTraffic: todayTraffic,
                                        weekTraffic: weekTraffic,
                                        tokenTotals: tokenTotals)
        var segments: [MenuBarStatusRenderer.Segment] = []
        for metric in order ?? displayPreferences.metricOrder where enabled.contains(metric) {
            for text in MenuBarStatusParts.parts(for: metric, context: context) {
                segments.append(MenuBarStatusRenderer.Segment(metric: metric, text: text))
            }
        }
        // 全部取不到值时回落下载速度，避免状态栏空白（与 makeStatusParts 同一口径）
        if segments.isEmpty {
            segments.append(MenuBarStatusRenderer.Segment(metric: .downSpeed,
                                                          text: context.speed(context.downSpeed)))
        }
        return segments
    }

    /// 状态栏片段上下文（两条渲染路径共用一份构造，避免单位口径分叉）
    func makeStatusContext(snapshot: SystemMetricsSnapshot?,
                           todayTraffic: UInt64,
                           weekTraffic: UInt64,
                           tokenTotals: HarnessUsageTotals?) -> MenuBarStatusContext {
        MenuBarStatusContext(downSpeed: max(monitor.downloadSpeed, 0),
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
    }

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
