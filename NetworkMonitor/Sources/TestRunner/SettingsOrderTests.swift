import Foundation
import NetworkMonitorCore

// MARK: - 设置项自定义排序

/// 顺序编解码 / 整理判据 / 菜单栏默认上屏顺序 / 旧 Int 键迁移
///
/// 只用内存存储（`InMemoryStorage`），不污染真实 UserDefaults。
func runSettingsOrderTests() {
    print("\n🧪 Testing SettingsOrder...")

    // MARK: 编解码

    assertEqual(SettingsOrderCoding.decode(nil), [], "缺键解码为空")
    assertEqual(SettingsOrderCoding.decode(""), [], "空串解码为空")
    assertEqual(SettingsOrderCoding.decode("a, b ,,c"), ["a", "b", "c"], "去空白、丢空项")
    assertEqual(SettingsOrderCoding.encode(["a", "b", "c"]), "a,b,c", "编码为逗号串")
    assertEqual(SettingsOrderCoding.encode([]), "", "空列表编码为空串")

    // MARK: 整理（normalize）

    let known = ["a", "b", "c", "d"]
    let def = known
    assertEqual(SettingsOrderCoding.normalize([], known: known, defaultOrder: def), def,
                "空顺序整理成默认顺序")
    assertEqual(SettingsOrderCoding.normalize(["c", "a"], known: known, defaultOrder: def), ["c", "a", "b", "d"],
                "保留已有顺序、缺失按默认顺序补尾")
    assertEqual(SettingsOrderCoding.normalize(["x", "a", "a", "b"], known: known, defaultOrder: def), ["a", "b", "c", "d"],
                "未知 id 丢弃、重复只留首次")
    assertEqual(SettingsOrderCoding.normalize(["d", "c", "b", "a"], known: known, defaultOrder: def), ["d", "c", "b", "a"],
                "完整逆序原样保留（不擅自排序）")
    assertEqual(SettingsOrderCoding.normalize(["z"], known: known, defaultOrder: def), def,
                "全非法回落默认顺序")
    assertEqual(SettingsOrderCoding.normalize(["a", "b", "c", "d", "e"], known: known, defaultOrder: def), def,
                "超集按已知项过滤")

    // MARK: 移动边界

    assertEqual(SettingsOrderStore.moved(def, id: "a", offset: -1), def, "首项上移不动")
    assertEqual(SettingsOrderStore.moved(def, id: "d", offset: 1), def, "末项下移不动")
    assertEqual(SettingsOrderStore.moved(def, id: "a", offset: 1), ["b", "a", "c", "d"], "相邻交换")
    assertEqual(SettingsOrderStore.moved(def, id: "b", offset: -1), ["b", "a", "c", "d"], "上移一位")
    assertEqual(SettingsOrderStore.moved(def, id: "zz", offset: 1), def, "未知 id 不动")

    // MARK: 存储层（缺键回落且不写回）

    let storage = InMemoryStorage()
    let key = SettingsOrderKey.menuBarMetrics
    assertEqual(SettingsOrderStore.order(forKey: key, known: known, defaultOrder: def, storage: storage), def,
                "缺键回落默认顺序")
    assertEqual(storage.object(forKey: key) == nil, true, "读路径不写回默认值")

    SettingsOrderStore.save(["c", "a"], forKey: key, storage: storage)
    assertEqual(SettingsOrderStore.order(forKey: key, known: known, defaultOrder: def, storage: storage),
                ["c", "a", "b", "d"], "写入后读回并补齐缺失项")
    assertEqual(storage.string(forKey: key), "c,a", "只存用户排序部分，不把补尾项写回")

    SettingsOrderStore.reset(forKey: key, storage: storage)
    assertEqual(storage.object(forKey: key) == nil, true, "恢复默认即删键")
    assertEqual(SettingsOrderStore.order(forKey: key, known: known, defaultOrder: def, storage: storage), def,
                "删键后回落默认")

    // MARK: 菜单栏默认上屏顺序（锁死）

    // 期望值 = 接入「自定义排序」之前 makeStatusParts 的硬编码 if 链顺序，
    // 新增指标追加到语义相邻处时**必须**同步改这里：改这个数组等于改变所有老用户的菜单栏外观。
    let expectedOrder: [MenuBarMetric] = [
        .downSpeed, .upSpeed,
        .cpu, .gpu, .memory, .memoryPressure, .diskFree, .diskIO, .wifi, .battery, .thermal, .load,
        .todayTraffic, .weekTraffic,
        .tokenToday, .tokenCacheHit, .tokenWeek,
    ]
    assertEqual(MenuBarMetric.defaultOrder, expectedOrder, "默认顺序 = 接入排序前的渲染顺序")
    assertEqual(MenuBarMetric.defaultOrder.count, MenuBarMetric.allCases.count, "默认顺序数量与指标总数一致")
    assertEqual(Set(MenuBarMetric.defaultOrder), Set(MenuBarMetric.allCases), "默认顺序不重不漏")
    assertEqual(Set(MenuBarMetric.stableIDs).count, MenuBarMetric.allCases.count, "稳定 id 唯一")
    assertEqual(MenuBarMetric.defaultOrderIDs.count, MenuBarMetric.defaultOrder.count, "id 列表与枚举一一对应")
    assertEqual(MenuBarMetric.defaultOrder.first, .downSpeed, "默认首项是下载速度（与旧实现一致）")
    assertEqual(MenuBarMetric.defaultOrder.last, .tokenWeek, "默认末项是 Token 7 天（与旧实现一致）")

    // 已移除的三项：从未上屏且没有数据源（峰值无采集、额度剩余不在菜单栏链路）
    assertEqual(MenuBarMetric(rawValue: "peakUp") == nil, true, "峰值上行已移除（无数据源）")
    assertEqual(MenuBarMetric(rawValue: "peakDown") == nil, true, "峰值下行已移除（无数据源）")
    assertEqual(MenuBarMetric(rawValue: "billingRemaining") == nil, true, "额度剩余已移除（菜单栏无数据链路）")

    // 默认顺序与声明顺序不同：这是不能用 allCases 兜底的证据
    assertEqual(MenuBarMetric.allCases != MenuBarMetric.defaultOrder, true,
                "声明顺序与上屏顺序不同，兜底必须用 defaultOrder")

    // MARK: 旧 Int 顺序键迁移

    let legacyIDs: [Int: String] = [0: "network", 1: "clipboard", 2: "transfer",
                                    3: "credits", 4: "token", 5: "system"]
    let knownTabs = ["network", "clipboard", "transfer", "credits", "token", "system"]
    assertEqual(SettingsOrderLegacy.migrateIntOrder(nil, legacyIDs: legacyIDs,
                                                    known: knownTabs, defaultOrder: knownTabs) == nil, true,
                "无旧键时不迁移")
    assertEqual(SettingsOrderLegacy.migrateIntOrder("", legacyIDs: legacyIDs,
                                                    known: knownTabs, defaultOrder: knownTabs) == nil, true,
                "空旧键不迁移")
    assertEqual(SettingsOrderLegacy.migrateIntOrder("abc", legacyIDs: legacyIDs,
                                                    known: knownTabs, defaultOrder: knownTabs) == nil, true,
                "旧键全非法时不迁移")
    assertEqual(SettingsOrderLegacy.migrateIntOrder("4,0", legacyIDs: legacyIDs,
                                                    known: knownTabs, defaultOrder: knownTabs),
                ["token", "network", "clipboard", "transfer", "credits", "system"],
                "旧 Int 顺序翻译成稳定 id 并补齐缺失分页")
    assertEqual(SettingsOrderLegacy.migrateIntOrder("5,9", legacyIDs: legacyIDs,
                                                    known: knownTabs, defaultOrder: knownTabs),
                ["system", "network", "clipboard", "transfer", "credits", "token"],
                "未知 Int 丢弃，其余按旧顺序保留")

    print("✅ SettingsOrder 设置项排序 works")
}
