import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏管理器（状态栏文本渲染）

/// 状态栏指标行组装 —— 从 `MenuBarManager.swift` 拆出（主文件接近单文件 15 KiB 上限）
///
/// 这里只做「偏好 + 快照 → 文本片段」，布局分行与刷新周期判据在 `MenuBarDisplayLogic`（NetworkMonitorUI），
/// 定时器与状态栏写回仍在主类。数值写法跟随「单位」偏好：short 紧凑、full 带空格、custom 回落 short。
extension MenuBarManager {

    /// 按「菜单栏显示」偏好组装当前指标文本片段
    /// - Parameters:
    ///   - enabled: 已启用的指标集合
    ///   - snapshot: 最近一帧系统快照（未装配系统监控时为 nil）
    ///   - todayTraffic: 今日上下行字节总量
    ///   - tokenTotals: Token 汇总（未装配 DSH 索引时为 nil）
    ///   - unitStyle: 数值单位写法
    /// - Returns: 至少一段（全部关闭时回落下载速度，避免状态栏空白）
    func makeStatusParts(enabled: Set<MenuBarMetric>,
                         snapshot: SystemMetricsSnapshot?,
                         todayTraffic: UInt64,
                         tokenTotals: HarnessUsageTotals?,
                         unitStyle: MenuBarDisplayLogic.UnitStyle) -> [String] {
        var parts: [String] = []
        /// 速率类数值：单位偏好决定紧凑写法还是带空格全称
        func speed(_ bps: Double) -> String {
            MenuBarDisplayLogic.speedText(shortText: formatSpeedShort(max(bps, 0)), unitStyle: unitStyle)
        }
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        if enabled.contains(.downSpeed) { parts.append("↓" + speed(downSpeed)) }
        if enabled.contains(.upSpeed) { parts.append("↑" + speed(upSpeed)) }
        if enabled.contains(.cpu), let cpu = snapshot?.cpu?.totalUsage { parts.append("CPU " + String(Int((cpu * 100).rounded())) + "%") }
        if enabled.contains(.gpu), let gpu = snapshot?.gpu { parts.append("GPU " + String(Int((gpu.utilization * 100).rounded())) + "%") }
        if enabled.contains(.memory), let mem = snapshot?.memory, mem.total > 0 { parts.append("MEM " + String(Int((Double(mem.used) / Double(mem.total) * 100).rounded())) + "%") }
        if enabled.contains(.memoryPressure), let mem = snapshot?.memory { parts.append("P " + mem.pressure.rawValue) }
        if enabled.contains(.diskFree), let disk = snapshot?.disk { parts.append("Disk " + String(format: "%.1f", Double(disk.total - disk.used) / 1073741824.0) + "G") }
        if enabled.contains(.diskIO), let disk = snapshot?.disk {
            if let r = disk.readBytesPerSecond { parts.append("R " + speed(r)) }
            if let w = disk.writeBytesPerSecond { parts.append("W " + speed(w)) }
        }
        if enabled.contains(.wifi), let wifi = snapshot?.wifi { parts.append("WiFi " + String(wifi.rssiDBm) + "dBm") }
        if enabled.contains(.battery), let bat = snapshot?.battery, let p = bat.percentage { parts.append("BAT " + String(Int((p * 100).rounded())) + "%") }
        if enabled.contains(.thermal), let t = snapshot?.thermal, let c = t.cpuTemperatureCelsius { parts.append("Temp " + String(Int(c.rounded())) + "°C") }
        if enabled.contains(.todayTraffic) { parts.append("Today " + speed(Double(todayTraffic))) }
        if enabled.contains(.tokenToday) { parts.append("Token " + speed(Double(tokenTotals?.today.totalTokens ?? 0))) }
        if enabled.contains(.tokenCacheHit), let rate = tokenTotals?.cacheHitRate { parts.append("HIT " + String(Int((rate * 100).rounded())) + "%") }
        if enabled.contains(.tokenWeek) { parts.append("7d " + speed(Double(tokenTotals?.thisWeek.totalTokens ?? 0))) }
        if parts.isEmpty { parts.append(speed(downSpeed)) }
        return parts
    }
}
