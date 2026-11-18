import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单面板分页目录（剪贴板分页下线后的偏好兼容）

/// 菜单面板「剪贴板」分页下线 —— 纯口径守卫
///
/// 背景：历史剪贴板只在屏幕底部的独立浮层里展示，菜单面板不再重复一份
/// （用户口径：「默认的历史剪贴板不需要显示在详情 tab」）。删掉这个 case 有两个坑：
///
/// 1. **顺序偏好**里存的是稳定 id（`settings.order.panelTabs`），老用户的串里还留着
///    `clipboard`。它必须被安全忽略，其余分页的相对顺序一个字都不能动。
/// 2. **旧格式 Int 顺序键**（`panel.tabs.order`，v1.23 及更早）里的编号是「声明位置」，
///    删 case 会让后面的编号整体前移。迁移必须查`冻结`的映射表，
///    而不是按当前枚举现推——现推会把旧数据的「2 = 传送」读成别的页。
func runPanelTabCatalogTests() {
    print("🧪 Testing panel tab catalog (clipboard tab retirement)...")

    // 当前在用的分页：5 个，且不含已下线的剪贴板
    assertEqual(PanelTabCatalog.stableIDs.count, 5, "菜单面板剩 5 个分页")
    assertEqual(PanelTabCatalog.stableIDs.contains("clipboard"), false,
                "当前分页 id 里不再有 clipboard")
    assertEqual(PanelTabCatalog.stableIDs,
                ["network", "transfer", "credits", "token", "system"],
                "分页默认顺序按声明顺序")

    // 已下线 id 单独登记，且不与在用 id 撞车
    assertEqual(PanelTabCatalog.retiredIDs, ["clipboard"], "下线 id 登记为 clipboard")
    for retired in PanelTabCatalog.retiredIDs {
        assertEqual(PanelTabCatalog.stableIDs.contains(retired), false,
                    "下线 id \(retired) 不在在用列表里")
    }

    // 冻结的旧 Int 映射：剪贴板占 1 号，后面的编号不因删 case 而前移
    assertEqual(PanelTabCatalog.legacyRawValueToStableID[0], "network", "旧 0 = 网络")
    assertEqual(PanelTabCatalog.legacyRawValueToStableID[1], "clipboard",
                "旧 1 = 剪贴板（已下线，但编号必须留在映射里）")
    assertEqual(PanelTabCatalog.legacyRawValueToStableID[2], "transfer",
                "旧 2 = 传送（删 case 后仍按冻结表读，不漂到额度）")
    assertEqual(PanelTabCatalog.legacyRawValueToStableID[3], "credits", "旧 3 = 额度")
    assertEqual(PanelTabCatalog.legacyRawValueToStableID[4], "token", "旧 4 = Token")
    assertEqual(PanelTabCatalog.legacyRawValueToStableID[5], "system", "旧 5 = 系统")
    assertEqual(PanelTabCatalog.legacyRawValueToStableID.count, 6, "历史上写出过 6 个编号")

    // 冻结表里除「已下线」以外的 id 必须与当前在用 id 完全一致（多一个 / 少一个都会让迁移读空）
    let frozenLiveIDs = Set(PanelTabCatalog.legacyRawValueToStableID.values)
        .subtracting(PanelTabCatalog.retiredIDs)
    assertEqual(frozenLiveIDs, Set(PanelTabCatalog.stableIDs),
                "冻结映射的在用 id 与当前分页集合一致")

    let known = PanelTabCatalog.knownIDs
    let defaultOrder = PanelTabCatalog.stableIDs

    // 老用户顺序里夹着 clipboard：被丢弃，其余顺序原样保留
    let stored = ["system", "clipboard", "network", "token", "credits", "transfer"]
    let normalized = SettingsOrderCoding.normalize(stored, known: known, defaultOrder: defaultOrder)
    assertEqual(normalized, ["system", "network", "token", "credits", "transfer"],
                "clipboard 被忽略，其余分页顺序一个字不动")

    // 老用户可见性里只有 clipboard：整份作废，回落到「全开」（不能让分页条空掉）
    let visibleOnlyClipboard = Set(SettingsOrderCoding.decode("clipboard").compactMap {
        PanelTabCatalog.stableIDs.contains($0) ? $0 : nil
    })
    assertEqual(visibleOnlyClipboard.isEmpty, true, "只勾了剪贴板的老配置解码后为空")
    let resolvedVisible = visibleOnlyClipboard.isEmpty ? Set(known) : visibleOnlyClipboard
    assertEqual(resolvedVisible, Set(PanelTabCatalog.stableIDs), "为空时回落到全部分页可见")

    // 旧 Int 顺序键迁移：2 必须是「传送」而不是顺移后的「额度」
    let migrated = SettingsOrderLegacy.migrateIntOrder("5,4,3,2,0",
                                                       legacyIDs: PanelTabCatalog.legacyRawValueToStableID,
                                                       known: known, defaultOrder: defaultOrder)
    assertEqual(migrated, ["system", "token", "credits", "transfer", "network"],
                "旧 Int 串按冻结表翻译，编号不前移")

    // 旧串里含 1（剪贴板）：翻译出来是 clipboard，随 normalize 丢弃，其余仍按旧编号对齐
    let migratedWithClipboard = SettingsOrderLegacy.migrateIntOrder(
        "1,5,4,3,2,0",
        legacyIDs: PanelTabCatalog.legacyRawValueToStableID,
        known: known, defaultOrder: defaultOrder)
    assertEqual(migratedWithClipboard, ["system", "token", "credits", "transfer", "network"],
                "旧串含剪贴板时只丢那一项，其余顺序不变")

    // 空 / 非法旧键不产生迁移结果（读路径据此判断「没有旧数据」）
    assertEqual(SettingsOrderLegacy.migrateIntOrder(nil,
                                                    legacyIDs: PanelTabCatalog.legacyRawValueToStableID,
                                                    known: known, defaultOrder: defaultOrder), nil,
                "没有旧键时不迁移")
    assertEqual(SettingsOrderLegacy.migrateIntOrder("9,7",
                                                    legacyIDs: PanelTabCatalog.legacyRawValueToStableID,
                                                    known: known, defaultOrder: defaultOrder), nil,
                "全部编号都认不出时不迁移")
}
