import AppKit
import NetworkMonitorCore

// MARK: - 菜单栏显示偏好

// 菜单栏指标枚举与其默认上屏顺序已下沉到 Core（`MenuBarMetric`）：
// 默认顺序要被 TestRunner 直接断言，可执行 target 无法被测试 target 引入。

enum MenuBarDensity: String, CaseIterable { case compact, comfortable, relaxed }
enum MenuBarLayout: String, CaseIterable { case singleLine, twoLine, card }
enum MenuBarUnitStyle: String, CaseIterable {
    case short, full, custom

    /// 下拉标题：custom 档没有自定义单位表（按 short 回落），标题里直接写明，
    /// 避免用户选了「自定义」却看不出任何变化
    var title: String {
        switch self {
        case .short: return "紧凑"
        case .full: return "全称"
        case .custom: return "自定义（暂等同紧凑）"
        }
    }
}

/// 菜单栏显示偏好（KeyValueStorage）
///
/// 两组键分工：`menuBar.metrics` 决定「显示哪些指标」，`settings.order.menuBar.metrics`
/// 决定「按什么顺序上屏」。顺序缺键时回落到 `MenuBarMetric.defaultOrder`（= 接入排序前的渲染顺序），
/// 读路径不回写，老用户升级后外观不变。
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

    // MARK: - 指标顺序

    /// 菜单栏上屏顺序；缺键 / 空串回落 `MenuBarMetric.defaultOrder`
    var metricOrder: [MenuBarMetric] {
        get {
            SettingsOrderStore.order(forKey: SettingsOrderKey.menuBarMetrics,
                                      known: MenuBarMetric.stableIDs,
                                      defaultOrder: MenuBarMetric.defaultOrderIDs,
                                      storage: storage)
                .compactMap(MenuBarMetric.init(rawValue:))
        }
        set {
            // 统一过一遍整理：调用方传进来的顺序可能缺项或含未知 id
            let ids = SettingsOrderCoding.normalize(newValue.map(\.rawValue),
                                                    known: MenuBarMetric.stableIDs,
                                                    defaultOrder: MenuBarMetric.defaultOrderIDs)
            SettingsOrderStore.save(ids, forKey: SettingsOrderKey.menuBarMetrics, storage: storage)
        }
    }

    /// 移动一个指标（-1 上移 / +1 下移），越界时不动
    func moveMetric(_ metric: MenuBarMetric, offset: Int) {
        let current = metricOrder.map(\.rawValue)
        let moved = SettingsOrderStore.moved(current, id: metric.rawValue, offset: offset)
        guard moved != current else { return }
        SettingsOrderStore.save(moved, forKey: SettingsOrderKey.menuBarMetrics, storage: storage)
    }

    /// 恢复默认顺序：删键后回落 `MenuBarMetric.defaultOrder`
    func resetMetricOrder() {
        SettingsOrderStore.reset(forKey: SettingsOrderKey.menuBarMetrics, storage: storage)
    }

    /// 是否已被用户改过顺序（设置页「恢复默认」按钮的可用态判据）
    var hasCustomMetricOrder: Bool {
        guard let raw = storage.string(forKey: SettingsOrderKey.menuBarMetrics) else { return false }
        return !raw.isEmpty
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

    /// 快捷模板：只改「显示哪些」，不改顺序（顺序是用户自己的排布，模板不覆盖）
    func applyTemplate(_ name: String) {
        let set: Set<MenuBarMetric>
        switch name {
        case "performance": set = [.downSpeed, .upSpeed, .cpu, .memory, .memoryPressure]
        case "token": set = [.downSpeed, .upSpeed, .tokenToday, .tokenCacheHit]
        case "network": set = [.upSpeed, .downSpeed, .todayTraffic, .weekTraffic]
        case "full": set = Set(MenuBarMetric.allCases)
        default: set = Set(MenuBarMetric.allCases.filter { $0.defaultEnabled })
        }
        enabledMetrics = set
        template = name
    }
}
