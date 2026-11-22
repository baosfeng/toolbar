import Foundation
import NetworkMonitorCore

// MARK: - 工具条顺序偏好（动作顺序 / 常驻工具顺序）

/// `SnipToolBarConfigurationResolver.resolve` 的两个顺序键分支
///
/// 与 `SnipToolBarConfigurationTests` 分文件：那边守「配置值类型 + 布局口径」，
/// 这里只守「顺序键与显隐解耦」这一条契约，两处各自读得完。
func runSnipToolBarOrderTests() {
    print("🧪 Testing snip toolbar order preferences...")

    // MARK: 撤销 / 重做：默认不上条（升级不改外观）

    // 默认可见集合刻意不含撤销 / 重做：它们并进 defaultOrder 就等于给每条老工具条加两个按钮
    assertEqual(SnipBarAction.defaultOrder, [.cancel, .copy, .save, .pin],
                "默认动作顺序仍是老四项")
    assertEqual(SnipBarAction.defaultOrder.contains(.undo), false, "defaultOrder 不含撤销")
    assertEqual(SnipBarAction.defaultOrder.contains(.redo), false, "defaultOrder 不含重做")
    // 枚举全量必须含它们，否则设置页不给入口、排序也登记不上
    assertEqual(SnipBarAction.allCases.contains(.undo), true, "枚举全量含撤销")
    assertEqual(SnipBarAction.allCases.contains(.redo), true, "枚举全量含重做")
    assertEqual(SnipBarAction.allOrderCases, SnipBarAction.allCases, "全序 = 枚举全量")
    assertEqual(SnipBarAction.allOrderCases.count, SnipBarAction.defaultOrder.count + 2,
                "全序比默认可见集合多撤销 / 重做两项")
    assertEqual(SnipBarAction.defaultHidden, [.undo, .redo], "缺键时默认隐藏的就是撤销 / 重做")
    assertEqual(SnipBarAction.undo.isHiddenByDefault, true, "撤销归扩展动作")
    assertEqual(SnipBarAction.redo.isHiddenByDefault, true, "重做归扩展动作")
    assertEqual(SnipBarAction.copy.isHiddenByDefault, false, "老四项不归扩展动作")
    assertEqual(SnipBarAction.undo.title, "撤销", "撤销标题")
    assertEqual(SnipBarAction.redo.title, "重做", "重做标题")
    assertEqual(SnipBarAction.undo.shortcutText, "⌘Z", "撤销快捷键文案")
    assertEqual(SnipBarAction.redo.shortcutText, "⌘Y", "重做快捷键文案")
    assertEqual(SnipBarAction.undo.isPrimary, false, "撤销不是强调色主按钮")
    assertEqual(SnipBarAction.redo.isPrimary, false, "重做不是强调色主按钮")

    // 缺键解析：老配置（两个显隐键都没写过）解析出来仍是原四个动作
    let legacyActions = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil)
    assertEqual(legacyActions.visibleActions, [.cancel, .copy, .save, .pin],
                "hiddenActions 缺键时解析结果仍是原四个动作")

    // 显隐键写空串（四个动作全开时 persist 的产物）也不算「启用撤销 / 重做」：
    // 这就是另立 utilityActions 的原因——空串无法区分「没设置过」与「全都打开」
    let emptyHidden = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: "")
    assertEqual(emptyHidden.visibleActions, [.cancel, .copy, .save, .pin],
                "hiddenActions 写空串时仍不带上撤销 / 重做")

    // 主动启用：只启用重做时只有它多出来，且排在老四项之后
    let redoOnly = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil,
        utilityActionsRaw: "redo")
    assertEqual(redoOnly.visibleActions, [.cancel, .copy, .save, .pin, .redo],
                "启用重做后它按全序排在老四项之后")

    // 两个都启用：顺序跟着 actionOrder 走（这里用缺键，回落「老四项 + 撤销 + 重做」）
    let both = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil,
        utilityActionsRaw: "undo,redo")
    assertEqual(both.visibleActions, [.cancel, .copy, .save, .pin, .undo, .redo],
                "启用撤销与重做后两者都在，且顺序稳定")

    // 未知 / 老四项写进启用键：只丢该项，不会把老四项从工具条上按掉
    let bogusUtility = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: nil, groupOrderRaw: nil, hiddenGroupsRaw: nil,
        primaryToolsRaw: nil, hiddenActionsRaw: nil,
        utilityActionsRaw: "bogus,copy")
    assertEqual(bogusUtility.visibleActions, [.cancel, .copy, .save, .pin],
                "启用键里的未知项与老四项名一律不生效")

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

    // MARK: 可用性快照（撤销 / 重做随标注栈变化）

    assertEqual(SnipBarActionAvailability.unavailable.isEnabled(.undo), false, "空栈：撤销不可用")
    assertEqual(SnipBarActionAvailability.unavailable.isEnabled(.redo), false, "空栈：重做不可用")
    for action in SnipBarAction.defaultOrder {
        assertEqual(SnipBarActionAvailability.unavailable.isEnabled(action), true,
                    "老四项恒可用：\(action.rawValue)")
    }
    let midStack = SnipBarActionAvailability(canUndo: true, canRedo: false)
    assertEqual(midStack.isEnabled(.undo), true, "栈里有图元：撤销可用")
    assertEqual(midStack.isEnabled(.redo), false, "刚加完还没撤：重做不可用")
    let undone = SnipBarActionAvailability(canUndo: false, canRedo: true)
    assertEqual(undone.isEnabled(.undo), false, "撤到空：撤销不可用")
    assertEqual(undone.isEnabled(.redo), true, "撤到空：重做可用")

    // 栈本身的口径（工具条置灰的证据来源）
    var stack = SnipAnnotationStack()
    assertEqual(stack.canUndo, false, "空栈不能撤销")
    assertEqual(stack.canRedo, false, "空栈不能重做")
    stack.add(SnipAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10)))
    assertEqual(stack.canUndo, true, "加一条后能撤销")
    assertEqual(stack.canRedo, false, "加一条后不能重做")
    stack.undo()
    assertEqual(stack.canUndo, false, "撤掉唯一一条后不能再撤")
    assertEqual(stack.canRedo, true, "撤掉唯一一条后能重做")

    // 同一域的第二块断言（两个显隐键分开落盘）另成一文，守住单文件 15 KiB 门禁
    runSnipToolBarActionPreferenceTests()

    print("✅ 工具条顺序偏好测试通过")
}