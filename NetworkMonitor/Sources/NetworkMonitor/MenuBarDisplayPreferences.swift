import AppKit
import NetworkMonitorCore

// MARK: - 菜单栏显示偏好

/// 菜单栏显示的指标与展示方式（KeyValueStorage）
enum MenuBarMetric: String, CaseIterable {
    // 网络
    case upSpeed, downSpeed, peakUp, peakDown, todayTraffic, weekTraffic
    // 系统
    case cpu, gpu, memory, memoryPressure, diskFree, diskIO, thermal, wifi, battery, load
    // Token
    case tokenToday, tokenCacheHit, tokenWeek
    // 额度
    case billingRemaining

    var displayName: String {
        switch self {
        case .upSpeed: return "上传速度"
        case .downSpeed: return "下载速度"
        case .peakUp: return "峰值上行"
        case .peakDown: return "峰值下行"
        case .todayTraffic: return "今日流量"
        case .weekTraffic: return "本周流量"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .memoryPressure: return "内存压力"
        case .diskFree: return "磁盘空闲"
        case .diskIO: return "磁盘 I/O"
        case .thermal: return "温度/功耗"
        case .wifi: return "Wi-Fi"
        case .battery: return "电量"
        case .load: return "负载"
        case .tokenToday: return "Token 今日"
        case .tokenCacheHit: return "缓存命中率"
        case .tokenWeek: return "Token 7 天"
        case .billingRemaining: return "额度剩余"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .upSpeed, .downSpeed: return true
        default: return false
        }
    }
}

enum MenuBarDensity: String, CaseIterable { case compact, comfortable, relaxed }
enum MenuBarLayout: String, CaseIterable { case singleLine, twoLine, card }
enum MenuBarUnitStyle: String, CaseIterable { case short, full, custom }

final class MenuBarDisplayPreferences {
    private let storage: any KeyValueStorage
    init(storage: any KeyValueStorage = AppContext.shared.storage) { self.storage = storage }

    private enum Key {
        static let metrics = "menuBar.metrics"
        static let density = "menuBar.density"
        static let layout = "menuBar.layout"
        static let unit = "menuBar.unitStyle"
        static let interval = "menuBar.refreshInterval"
        static let template = "menuBar.template"
        static let alertsEnabled = "menuBar.alertsEnabled"
        static let cpuAlert = "menuBar.cpuAlert"
        static let memoryAlert = "menuBar.memoryAlert"
    }

    var enabledMetrics: Set<MenuBarMetric> {
        get {
            guard let raw = storage.string(forKey: Key.metrics), !raw.isEmpty else {
                return Set(MenuBarMetric.allCases.filter { $0.defaultEnabled })
            }
            let values = raw.split(separator: ",").map(String.init)
            let set = Set(values.compactMap { MenuBarMetric(rawValue: $0) })
            return set.isEmpty ? Set(MenuBarMetric.allCases.filter { $0.defaultEnabled }) : set
        }
        set {
            storage.set(newValue.map(\.rawValue).joined(separator: ","), forKey: Key.metrics)
        }
    }

    func setMetric(_ metric: MenuBarMetric, enabled: Bool) {
        var set = enabledMetrics
        if enabled { set.insert(metric) } else { set.remove(metric) }
        if set.isEmpty { set.insert(.downSpeed) }
        enabledMetrics = set
    }

    var density: MenuBarDensity {
        get { MenuBarDensity(rawValue: storage.string(forKey: Key.density) ?? "") ?? .compact }
        set { storage.set(newValue.rawValue, forKey: Key.density) }
    }
    var layout: MenuBarLayout {
        get { MenuBarLayout(rawValue: storage.string(forKey: Key.layout) ?? "") ?? .singleLine }
        set { storage.set(newValue.rawValue, forKey: Key.layout) }
    }
    var unitStyle: MenuBarUnitStyle {
        get { MenuBarUnitStyle(rawValue: storage.string(forKey: Key.unit) ?? "") ?? .short }
        set { storage.set(newValue.rawValue, forKey: Key.unit) }
    }
    var refreshInterval: TimeInterval {
        get {
            let v = storage.double(forKey: Key.interval)
            return v > 0 ? min(max(v, 1), 10) : 1
        }
        set { storage.set(min(max(newValue, 1), 10), forKey: Key.interval) }
    }
    var template: String {
        get { storage.string(forKey: Key.template) ?? "minimal" }
        set { storage.set(newValue, forKey: Key.template) }
    }

    var alertsEnabled: Bool {
        get { storage.object(forKey: Key.alertsEnabled) == nil ? false : storage.bool(forKey: Key.alertsEnabled) }
        set { storage.set(newValue, forKey: Key.alertsEnabled) }
    }
    var cpuAlertThreshold: Double {
        get {
            let v = storage.double(forKey: Key.cpuAlert)
            return v > 0 ? v : 0.8
        }
        set { storage.set(newValue, forKey: Key.cpuAlert) }
    }
    var memoryAlertThreshold: Double {
        get {
            let v = storage.double(forKey: Key.memoryAlert)
            return v > 0 ? v : 0.85
        }
        set { storage.set(newValue, forKey: Key.memoryAlert) }
    }

    func applyTemplate(_ name: String) {
        let set: Set<MenuBarMetric>
        switch name {
        case "performance": set = [.downSpeed, .upSpeed, .cpu, .memory, .memoryPressure]
        case "token": set = [.downSpeed, .upSpeed, .tokenToday, .tokenCacheHit]
        case "network": set = [.upSpeed, .downSpeed, .peakUp, .peakDown, .todayTraffic]
        case "full": set = Set(MenuBarMetric.allCases)
        default: set = Set(MenuBarMetric.allCases.filter { $0.defaultEnabled })
        }
        enabledMetrics = set
        template = name
    }
}
