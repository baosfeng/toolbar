import AppKit
import NetworkMonitorCore

// MARK: - 面板分页偏好

/// 面板分页可见性与顺序（KeyValueStorage）
///
/// 与菜单栏主菜单/右键菜单入口解耦；隐藏分页后数字键与左右循环只在可见分页内切换。
final class PanelTabPreferences {
    private let storage: any KeyValueStorage

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    private enum Key {
        static let order = "panel.tabs.order"
        static let visible = "panel.tabs.visible"
    }

    /// 默认顺序（全量）
    static let defaultOrder: [MenuPanelTab] = MenuPanelTab.allCases
    static let defaultVisible: Set<MenuPanelTab> = Set(MenuPanelTab.allCases)

    /// 已保存的顺序；缺失时回退 allCases
    var tabOrder: [MenuPanelTab] {
        get {
            guard let raw = storage.string(forKey: Key.order), !raw.isEmpty else {
                return Self.defaultOrder
            }
            let ints = raw.split(separator: ",").compactMap { Int($0) }
            let tabs = ints.compactMap { MenuPanelTab(rawValue: $0) }
            // 兜底：补齐缺漏的 tab，避免老版本新增分页后丢失
            var result = tabs
            for tab in Self.defaultOrder where !result.contains(tab) { result.append(tab) }
            return result.isEmpty ? Self.defaultOrder : result
        }
        set {
            storage.set(newValue.map(String.init).joined(separator: ","), forKey: Key.order)
        }
    }

    /// 已保存的可见集合；缺失时全开
    var visibleTabs: Set<MenuPanelTab> {
        get {
            guard let raw = storage.string(forKey: Key.visible), !raw.isEmpty else {
                return Self.defaultVisible
            }
            let ints = raw.split(separator: ",").compactMap { Int($0) }
            let set = Set(ints.compactMap { MenuPanelTab(rawValue: $0) })
            return set.isEmpty ? Self.defaultVisible : set
        }
        set {
            // 至少保留一项
            let filtered = newValue.isEmpty ? [tabOrder.first ?? .network] : Array(newValue)
            storage.set(filtered.map(String.init).joined(separator: ","), forKey: Key.visible)
        }
    }

    /// 可见且按顺序排列的分页
    var orderedVisibleTabs: [MenuPanelTab] {
        tabOrder.filter { visibleTabs.contains($0) }
    }

    func setVisible(_ visible: Bool, for tab: MenuPanelTab) {
        var set = visibleTabs
        if visible { set.insert(tab) } else { set.remove(tab) }
        if set.isEmpty { set.insert(tab) }
        visibleTabs = set
    }

    func move(_ tab: MenuPanelTab, offset: Int) {
        var order = tabOrder
        guard let index = order.firstIndex(of: tab) else { return }
        let target = max(0, min(order.count - 1, index + offset))
        guard target != index else { return }
        order.remove(at: index)
        order.insert(tab, at: target)
        tabOrder = order
    }

    func reset() {
        storage.removeObject(forKey: Key.order)
        storage.removeObject(forKey: Key.visible)
    }
}
