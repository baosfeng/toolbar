import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏管理器（状态栏文本渲染）

/// 状态栏指标行组装 —— 顺序由「菜单栏指标顺序」偏好决定，片段口径收在 `statusParts(for:context:)` 白名单里
///
/// 从 `MenuBarManager.swift` 拆出（主文件接近单文件 15 KiB 上限）。
/// 布局分行与刷新周期判据在 `MenuBarDisplayLogic`（NetworkMonitorUI），定时器与状态栏写回仍在主类。
/// 数值写法跟随「单位」偏好：short 紧凑、full 带空格、custom 回落 short。
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
    ///   - unitStyle: 数值单位写法
    /// - Returns: 至少一段（全部关闭时回落下载速度，避免状态栏空白）
    func makeStatusParts(enabled: Set<MenuBarMetric>,
                         order: [MenuBarMetric]? = nil,
                         snapshot: SystemMetricsSnapshot?,
                         todayTraffic: UInt64,
                         weekTraffic: UInt64,
                         tokenTotals: HarnessUsageTotals?,
                         unitStyle: MenuBarDisplayLogic.UnitStyle) -> [String] {
        let context = StatusPartContext(downSpeed: max(monitor.downloadSpeed, 0),
                                        upSpeed: max(monitor.uploadSpeed, 0),
                                        snapshot: snapshot,
                                        todayTraffic: todayTraffic,
                                        weekTraffic: weekTraffic,
                                        tokenTotals: tokenTotals,
                                        unitStyle: unitStyle)
        let ordered = order ?? displayPreferences.metricOrder
        var parts: [String] = []
        for metric in ordered where enabled.contains(metric) {
            parts.append(contentsOf: statusParts(for: metric, context: context))
        }
        // 兜底：全部关闭或全部取不到值时仍显示下载速度，避免状态栏空白
        if parts.isEmpty { parts.append(context.speed(context.downSpeed)) }
        return parts
    }

    /// 单个指标的状态栏片段
    ///
    /// 白名单写法：一个指标一个分支，返回空数组表示「当前取不到值」——
    /// 不给「—」占位，避免菜单栏被无意义字符占宽。
    private func statusParts(for metric: MenuBarMetric, context: StatusPartContext) -> [String] {
        switch metric {
        case .downSpeed:
            return ["↓" + context.speed(context.downSpeed)]
        case .upSpeed:
            return ["↑" + context.speed(context.upSpeed)]
        case .cpu:
            guard let cpu = context.snapshot?.cpu?.totalUsage else { return [] }
            return ["CPU " + String(Int((cpu * 100).rounded())) + "%"]
        case .gpu:
            guard let gpu = context.snapshot?.gpu else { return [] }
            return ["GPU " + String(Int((gpu.utilization * 100).rounded())) + "%"]
        case .memory:
            guard let mem = context.snapshot?.memory, mem.total > 0 else { return [] }
            return ["MEM " + String(Int((Double(mem.used) / Double(mem.total) * 100).rounded())) + "%"]
        case .memoryPressure:
            guard let mem = context.snapshot?.memory else { return [] }
            return ["P " + mem.pressure.rawValue]
        case .diskFree:
            guard let disk = context.snapshot?.disk else { return [] }
            return ["Disk " + String(format: "%.1f", Double(disk.total - disk.used) / 1073741824.0) + "G"]
        case .diskIO:
            guard let disk = context.snapshot?.disk else { return [] }
            var parts: [String] = []
            if let r = disk.readBytesPerSecond { parts.append("R " + context.speed(r)) }
            if let w = disk.writeBytesPerSecond { parts.append("W " + context.speed(w)) }
            return parts
        case .wifi:
            guard let wifi = context.snapshot?.wifi else { return [] }
            return ["WiFi " + String(wifi.rssiDBm) + "dBm"]
        case .battery:
            guard let bat = context.snapshot?.battery, let p = bat.percentage else { return [] }
            return ["BAT " + String(Int((p * 100).rounded())) + "%"]
        case .thermal:
            guard let c = context.snapshot?.thermal?.cpuTemperatureCelsius else { return [] }
            return ["Temp " + String(Int(c.rounded())) + "°C"]
        case .load:
            guard let load = context.snapshot?.load else { return [] }
            return ["L " + String(format: "%.2f", load.load1)]
        case .todayTraffic:
            return ["Today " + context.speed(Double(context.todayTraffic))]
        case .weekTraffic:
            return ["Wk " + context.speed(Double(context.weekTraffic))]
        case .tokenToday:
            return ["Token " + context.speed(Double(context.tokenTotals?.today.totalTokens ?? 0))]
        case .tokenCacheHit:
            guard let rate = context.tokenTotals?.cacheHitRate else { return [] }
            return ["HIT " + String(Int((rate * 100).rounded())) + "%"]
        case .tokenWeek:
            return ["7d " + context.speed(Double(context.tokenTotals?.thisWeek.totalTokens ?? 0))]
        }
    }
}

// MARK: - 片段上下文

/// 状态栏片段组装所需的数据源 —— 一次 update 内构造一份，逐指标复用
struct StatusPartContext {
    /// 当前下载速度（字节/秒）
    let downSpeed: Double
    /// 当前上传速度（字节/秒）
    let upSpeed: Double
    /// 最近一帧系统快照
    let snapshot: SystemMetricsSnapshot?
    /// 今日流量（上下行合计）
    let todayTraffic: UInt64
    /// 近 7 日流量合计
    let weekTraffic: UInt64
    /// Token 汇总
    let tokenTotals: HarnessUsageTotals?
    /// 数值单位写法
    let unitStyle: MenuBarDisplayLogic.UnitStyle

    /// 速率类数值：单位偏好决定紧凑写法还是带空格全称
    func speed(_ bps: Double) -> String {
        MenuBarDisplayLogic.speedText(shortText: formatSpeedShort(max(bps, 0)), unitStyle: unitStyle)
    }
}
