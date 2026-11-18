import Foundation
import NetworkMonitorCore

// MARK: - 工具条顺序偏好（动作顺序 / 常驻工具顺序）

/// `SnipToolBarConfigurationResolver.resolve` 的两个顺序键分支
///
/// 与 `SnipToolBarConfigurationTests` 分文件：那边守「配置值类型 + 布局口径」，
/// 这里只守「顺序键与显隐解耦」这一条契约，两处各自读得完。
func runSnipToolBarOrderTests() {
    print("🧪 Testing snip toolbar order preferences...")

    // MARK: 输出动作顺序键

    // 顺序键生效：存的顺序就是工具条上的排列，缺项按 defaultOrder 补尾
    let ordered = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil,
        actionOrderRaw: "pin,cancel")
    assertEqual(ordered.visibleActions, [.pin, .cancel, .copy, .save],
                "动作顺序键生效，缺项按 defaultOrder 补尾")

    // 顺序键含未知动作名：只丢该项，其余照存顺序
    let withUnknown = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil,
        actionOrderRaw: "pin,bogus,cancel")
    assertEqual(withUnknown.visibleActions, [.pin, .cancel, .copy, .save],
                "动作顺序键含未知项时只丢该项")

    // 顺序与显隐解耦：关掉的动作不占输出位，其余项相对顺序不变
    let hidden = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: "cancel",
        actionOrderRaw: "pin,cancel,copy,save")
    assertEqual(hidden.visibleActions, [.pin, .copy, .save],
                "隐藏动作只影响可见集合，不改变其余项的相对顺序")
    // 重新打开：回到它在顺序偏好里的原席次（第 2 位），不排到末尾
    let reopened = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil,
        actionOrderRaw: "pin,cancel,copy,save")
    assertEqual(reopened.visibleActions, [.pin, .cancel, .copy, .save],
                "关掉再打开的动作回到原席次、不排到末尾")

    // 缺键回落 defaultOrder
    let noActionKey = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil)
    assertEqual(noActionKey.visibleActions, SnipBarAction.defaultOrder,
                "动作顺序键缺省时回落 defaultOrder")

    // MARK: 常驻工具顺序键

    assertEqual(SnipTool.defaultOrder, SnipTool.primary + SnipTool.overflow,
                "默认全序 = 常驻四工具打头，其余按声明顺序跟随")

    // 顺序键生效，缺项按默认顺序补尾，再按常驻集合过滤
    let toolOrdered = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: "rectangle,arrow,text,mosaic", hiddenActionsRaw: nil,
        primaryToolOrderRaw: "text,arrow")
    assertEqual(toolOrdered.primaryTools, [.text, .arrow, .rectangle, .mosaic],
                "常驻工具顺序键生效，缺项按默认顺序补尾")

    // 含未知工具名：只丢该项
    let toolUnknown = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: "rectangle,arrow,text,mosaic", hiddenActionsRaw: nil,
        primaryToolOrderRaw: "text,bogus,arrow")
    assertEqual(toolUnknown.primaryTools, [.text, .arrow, .rectangle, .mosaic],
                "常驻工具顺序键含未知项时只丢该项")

    // 与常驻集合解耦：只剩一个常驻工具时工具条上就是那一个
    let single = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: "arrow", hiddenActionsRaw: nil,
        primaryToolOrderRaw: "text,arrow,rectangle")
    assertEqual(single.primaryTools, [.arrow], "常驻集合只有一个时只摆那一个")

    // 关掉再打开：按顺序偏好回到原席次（arrow 在 rectangle 前），而不是排到末尾
    let toolReopened = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: "arrow,rectangle", hiddenActionsRaw: nil,
        primaryToolOrderRaw: "text,arrow,rectangle")
    assertEqual(toolReopened.primaryTools, [.arrow, .rectangle],
                "重新打开的常驻工具回到原席次、不排到末尾")

    // 缺键回落 SnipTool.primary
    let noToolKey = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil, primaryToolOrderRaw: nil)
    assertEqual(noToolKey.primaryTools, SnipTool.primary,
                "常驻工具顺序键缺省时回落 SnipTool.primary")

    // 全常驻且缺顺序键时，整个全序等于 SnipTool.defaultOrder
    let allResident = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: SnipToolBarListCoding.encode(SnipTool.allCases.map(\.rawValue)),
        hiddenActionsRaw: nil)
    assertEqual(allResident.primaryTools, SnipTool.defaultOrder,
                "缺顺序键时全常驻按默认全序排列")

    // MARK: 顺序键归 SettingsOrderStore 独占

    // persist 只写显隐，不碰两个顺序键：否则「关掉一项」会把它的席次从全序里抹掉
    let storage = InMemoryStorage()
    SettingsOrderStore.save(["pin", "cancel", "copy", "save"],
                            forKey: SnipToolBarPreferenceKey.actionOrder, storage: storage)
    SettingsOrderStore.save(SnipTool.defaultOrder.map(\.rawValue),
                            forKey: SnipToolBarPreferenceKey.primaryToolOrder, storage: storage)
    // 可见动作只留三项（取消被关掉），常驻工具只留两个
    SnipToolBarConfigurationResolver.persist(
        SnipToolBarConfiguration(primaryTools: [.rectangle, .text],
                                 visibleActions: [.copy, .pin, .save]),
        storage: storage)
    assertEqual(storage.string(forKey: SnipToolBarPreferenceKey.actionOrder),
                "pin,cancel,copy,save", "persist 不回写动作顺序键")
    assertEqual(storage.string(forKey: SnipToolBarPreferenceKey.primaryToolOrder),
                SnipToolBarListCoding.encode(SnipTool.defaultOrder.map(\.rawValue)),
                "persist 不回写常驻工具顺序键")
    // 读完仍是顺序键决定排列，只是把被隐藏的那一项过滤掉
    assertEqual(SnipToolBarConfigurationResolver.load(storage: storage).visibleActions,
                [.pin, .copy, .save], "load 按顺序键排列动作并只过滤掉被隐藏的一项")
    assertEqual(SnipToolBarConfigurationResolver.load(storage: storage).primaryTools,
                [.rectangle, .text], "load 按顺序键排列常驻工具并只留常驻项")

    // 恢复默认 = 删键，下次读回落代码默认顺序
    SettingsOrderStore.reset(forKey: SnipToolBarPreferenceKey.primaryToolOrder, storage: storage)
    assertEqual(storage.string(forKey: SnipToolBarPreferenceKey.primaryToolOrder), nil,
                "恢复默认删掉常驻工具顺序键")
    assertEqual(SnipToolBarConfigurationResolver.load(storage: storage).primaryTools,
                [.rectangle, .text], "顺序键删除后按默认全序过滤常驻集合")

    print("✅ 工具条顺序偏好测试通过")
}
