import AppKit
import NetworkMonitorCore

// MARK: - 面板分页偏好

/// 面板分页可见性与顺序（KeyValueStorage）
///
/// 与菜单栏主菜单/右键菜单入口解耦；隐藏分页后数字键与左右循环只在可见分页内切换。
///
/// 顺序键经历一次格式迁移：
/// - 旧：`panel.tabs.order` / `panel.tabs.visible`，逗号分隔的 **Int rawValue**
/// - 新：`settings.order.panelTabs` / `settings.order.panelTabs.visible`，逗号分隔的 **稳定 id**
///
/// 迁移在首次读取时执行（读到旧键才写新键并删旧键），属于「格式转换」而非「读路径回写默认值」。
final class PanelTabPreferences {
    private let storage: any KeyValueStorage

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    private enum Key {
        static let order = SettingsOrderKey.panelTabs
        static let visible = "settings.order.panelTabs.visible"
        /// 旧格式（v1.23 及更早）
        static let legacyOrder = "panel.tabs.order"
        static let legacyVisible = "panel.tabs.visible"
    }

    /// 默认顺序（全量）
    static let defaultOrder: [MenuPanelTab] = MenuPanelTab.allCases
    static let defaultVisible: Set<MenuPanelTab> = Set(MenuPanelTab.allCases)

    private static var knownIDs: [String] { MenuPanelTab.allCases.map(\.stableID) }
    private static var defaultOrderIDs: [String] { defaultOrder.map(\.stableID) }
    /// 旧 Int rawValue → 稳定 id（迁移判据；Core 侧可单测）
    private static var legacyIDMap: [Int: String] {
        Dictionary(uniqueKeysWithValues: MenuPanelTab.allCases.map { ($0.rawValue, $0.stableID) })
    }

    /// 已保存的顺序；缺键回退 allCases
    var tabOrder: [MenuPanelTab] {
        get {
            migrateLegacyKeysIfNeeded()
            let tabs = SettingsOrderStore.order(forKey: Key.order,
                                                known: Self.knownIDs,
                                                defaultOrder: Self.defaultOrderIDs,
                                                storage: storage)
                .compactMap(Self.tab(fromStableID:))
            return tabs.isEmpty ? Self.defaultOrder : tabs
        }
        set {
            let ids = SettingsOrderCoding.normalize(newValue.map(\.stableID),
                                                    known: Self.knownIDs,
                                                    defaultOrder: Self.defaultOrderIDs)
            SettingsOrderStore.save(ids, forKey: Key.order, storage: storage)
        }
    }

    /// 已保存的可见集合；缺失时全开
    var visibleTabs: Set<MenuPanelTab> {
        get {
            migrateLegacyKeysIfNeeded()
            guard let raw = storage.string(forKey: Key.visible), !raw.isEmpty else {
                return Self.defaultVisible
            }
            let set = Set(SettingsOrderCoding.decode(raw).compactMap(Self.tab(fromStableID:)))
            return set.isEmpty ? Self.defaultVisible : set
        }
        set {
            // 至少保留一项
            let filtered = newValue.isEmpty ? [tabOrder.first ?? .network] : Array(newValue)
            let ids = filtered.map(\.stableID)
            storage.set(SettingsOrderCoding.encode(ids), forKey: Key.visible)
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
        let current = tabOrder
        guard let index = current.firstIndex(of: tab) else { return }
        let target = max(0, min(current.count - 1, index + offset))
        guard target != index else { return }
        var order = current
        order.remove(at: index)
        order.insert(tab, at: target)
        tabOrder = order
    }

    /// 恢复默认：删新键与遗留旧键（下次读回落 allCases）
    func reset() {
        storage.removeObject(forKey: Key.order)
        storage.removeObject(forKey: Key.visible)
        storage.removeObject(forKey: Key.legacyOrder)
        storage.removeObject(forKey: Key.legacyVisible)
    }

    // MARK: - 稳定 id

    /// 按稳定 id 反查分页（未知 id 返回 nil，由 normalize 之外的兜底丢弃）
    static func tab(fromStableID id: String) -> MenuPanelTab? {
        MenuPanelTab.allCases.first { $0.stableID == id }
    }

    // MARK: - 旧格式迁移

    /// 旧 Int rawValue 键 → 新稳定 id 键（一次性、幂等；读到旧键才写）
    private func migrateLegacyKeysIfNeeded() {
        if let migrated = SettingsOrderLegacy.migrateIntOrder(storage.string(forKey: Key.legacyOrder),
                                                              legacyIDs: Self.legacyIDMap,
                                                              known: Self.knownIDs,
                                                              defaultOrder: Self.defaultOrderIDs) {
            SettingsOrderStore.save(migrated, forKey: Key.order, storage: storage)
            storage.removeObject(forKey: Key.legacyOrder)
        }
        if let migratedVisible = SettingsOrderLegacy.migrateIntOrder(storage.string(forKey: Key.legacyVisible),
                                                                     legacyIDs: Self.legacyIDMap,
                                                                     known: Self.knownIDs,
                                                                     defaultOrder: Self.defaultOrderIDs) {
            SettingsOrderStore.save(migratedVisible, forKey: Key.visible, storage: storage)
            storage.removeObject(forKey: Key.legacyVisible)
        }
    }
}
