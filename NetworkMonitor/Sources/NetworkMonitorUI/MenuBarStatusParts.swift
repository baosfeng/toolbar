import Foundation
import NetworkMonitorCore

// MARK: - 菜单栏状态栏片段（纯逻辑）

/// 状态栏片段渲染 —— 17 项指标的**唯一白名单**，从 App 的
/// `MenuBarManager+StatusTitle.swift` 迁来（视图层只负责取数、拼分隔符、写回按钮）
///
/// 为什么搬到这里：这 17 个分支是「哪一项出什么文本」的全部口径，含标签、单位与
/// 「取不到值就返回空数组」的约定。放在可执行 target 里 TestRunner 够不着，
/// 前缀 / 单位这类回归只能靠眼力 —— 搬进 UI 库后 `MenuBarLabelTests` 可以逐项断言。
public enum MenuBarStatusParts {

    /// 单个指标的状态栏片段
    ///
    /// 白名单写法：一个指标一个分支，返回空数组表示「当前取不到值」——
    /// 不给「—」占位，避免菜单栏被无意义字符占宽。
    public static func parts(for metric: MenuBarMetric, context: MenuBarStatusContext) -> [String] {
        switch metric {
        case .downSpeed:
            return [label(metric, context) + context.speed(context.downSpeed)]
        case .upSpeed:
            return [label(metric, context) + context.speed(context.upSpeed)]
        case .cpu:
            guard let cpu = context.snapshot?.cpu?.totalUsage else { return [] }
            return [label(metric, context) + percent(cpu)]
        case .gpu:
            guard let gpu = context.snapshot?.gpu else { return [] }
            return [label(metric, context) + percent(gpu.utilization)]
        case .memory:
            guard let mem = context.snapshot?.memory, mem.total > 0 else { return [] }
            return [label(metric, context) + percent(Double(mem.used) / Double(mem.total))]
        case .memoryPressure:
            guard let mem = context.snapshot?.memory else { return [] }
            return [label(metric, context) + mem.pressure.rawValue]
        case .diskFree:
            guard let disk = context.snapshot?.disk else { return [] }
            let free = Double(disk.total - disk.used) / 1_073_741_824
            return [label(metric, context) + String(format: "%.1f", free) + "G"]
        case .diskIO:
            guard let disk = context.snapshot?.disk else { return [] }
            var pieces: [String] = []
            if let read = disk.readBytesPerSecond {
                pieces.append(label(metric, context) + context.speed(read))
            }
            if let write = disk.writeBytesPerSecond {
                pieces.append(context.secondaryLabel(metric) + context.speed(write))
            }
            return pieces
        case .wifi:
            guard let wifi = context.snapshot?.wifi else { return [] }
            return [label(metric, context) + String(wifi.rssiDBm) + "dBm"]
        case .battery:
            guard let battery = context.snapshot?.battery, let level = battery.percentage else { return [] }
            return [label(metric, context) + percent(level)]
        case .thermal:
            guard let celsius = context.snapshot?.thermal?.cpuTemperatureCelsius else { return [] }
            return [label(metric, context) + String(Int(celsius.rounded())) + "°C"]
        case .load:
            guard let load = context.snapshot?.load else { return [] }
            return [label(metric, context) + String(format: "%.2f", load.load1)]
        case .todayTraffic:
            return [label(metric, context) + context.count(Double(context.todayTraffic))]
        case .weekTraffic:
            return [label(metric, context) + context.count(Double(context.weekTraffic))]
        case .tokenToday:
            let tokens = Double(context.tokenTotals?.today.totalTokens ?? 0)
            return [label(metric, context) + context.count(tokens)]
        case .tokenCacheHit:
            guard let rate = context.tokenTotals?.cacheHitRate else { return [] }
            return [label(metric, context) + percent(rate)]
        case .tokenWeek:
            let tokens = Double(context.tokenTotals?.thisWeek.totalTokens ?? 0)
            return [label(metric, context) + context.count(tokens)]
        }
    }

    /// 按顺序组装所有已启用指标的片段
    ///
    /// - Returns: 至少一段（全部关闭或全部取不到值时回落下载速度，避免状态栏空白）
    public static func make(enabled: Set<MenuBarMetric>,
                            order: [MenuBarMetric],
                            context: MenuBarStatusContext) -> [String] {
        var pieces: [String] = []
        for metric in order where enabled.contains(metric) {
            pieces.append(contentsOf: parts(for: metric, context: context))
        }
        if pieces.isEmpty { pieces.append(context.speed(context.downSpeed)) }
        return pieces
    }

    // MARK: - 内部

    private static func label(_ metric: MenuBarMetric, _ context: MenuBarStatusContext) -> String {
        MenuBarLabelResolver.primaryLabel(for: metric,
                                          style: context.labelStyle,
                                          customLabels: context.customLabels)
    }

    private static func percent(_ fraction: Double) -> String {
        String(Int((fraction * 100).rounded())) + "%"
    }
}

// MARK: - 片段上下文

/// 状态栏片段组装所需的数据源 —— 一次 update 内构造一份，逐指标复用
///
/// 三条单位链路各管一段，互不覆盖：
/// - `unitStyle`（菜单栏「单位」）：紧凑 `1.2M` / 带空格全称 `1.2 MB/s`
/// - `numberUnitStyle`（设置页「数值单位」）：计数的量级写法，中文档走万 / 亿
/// - `labelStyle` + `customLabels`（本次新增）：前缀多长、谁覆盖谁
public struct MenuBarStatusContext: Sendable {

    /// 当前下载速度（字节/秒）
    public let downSpeed: Double
    /// 当前上传速度（字节/秒）
    public let upSpeed: Double
    /// 最近一帧系统快照
    public let snapshot: SystemMetricsSnapshot?
    /// 今日流量（上下行合计，字节）
    public let todayTraffic: UInt64
    /// 近 7 日流量合计（字节）
    public let weekTraffic: UInt64
    /// Token 汇总
    public let tokenTotals: HarnessUsageTotals?
    /// 菜单栏数值写法（紧凑 / 全称）
    public let unitStyle: MenuBarDisplayLogic.UnitStyle
    /// 设置页「数值单位」档（计数类的量级口径）
    public let numberUnitStyle: NumberUnitStyle
    /// 前缀档（完整 / 短标签）
    public let labelStyle: MenuBarLabelStyle
    /// 逐项自定义前缀（偏好键 `menuBar.customLabels`）
    public let customLabels: [String: String]

    public init(downSpeed: Double,
                upSpeed: Double,
                snapshot: SystemMetricsSnapshot?,
                todayTraffic: UInt64,
                weekTraffic: UInt64,
                tokenTotals: HarnessUsageTotals?,
                unitStyle: MenuBarDisplayLogic.UnitStyle,
                numberUnitStyle: NumberUnitStyle = .automatic,
                labelStyle: MenuBarLabelStyle = .full,
                customLabels: [String: String] = [:]) {
        self.downSpeed = downSpeed
        self.upSpeed = upSpeed
        self.snapshot = snapshot
        self.todayTraffic = todayTraffic
        self.weekTraffic = weekTraffic
        self.tokenTotals = tokenTotals
        self.unitStyle = unitStyle
        self.numberUnitStyle = numberUnitStyle
        self.labelStyle = labelStyle
        self.customLabels = customLabels
    }

    /// 速率类数值（字节/秒）：单位偏好决定紧凑写法还是带空格全称
    public func speed(_ bytesPerSecond: Double) -> String {
        MenuBarDisplayLogic.speedText(shortText: formatSpeedShort(max(bytesPerSecond, 0)),
                                      unitStyle: unitStyle)
    }

    /// 计数类数值（流量总量 / Token 数）：量级跟随「数值单位」，full 档不再带 `/s`
    public func count(_ value: Double) -> String {
        MenuBarDisplayLogic.countText(value,
                                      numberStyle: numberUnitStyle,
                                      unitStyle: unitStyle)
    }

    /// 磁盘 I/O 的第二片段前缀（只有它有第二段）
    public func secondaryLabel(_ metric: MenuBarMetric) -> String {
        MenuBarLabelResolver.secondaryLabel(for: metric,
                                            style: labelStyle,
                                            customLabels: customLabels) ?? ""
    }
}
