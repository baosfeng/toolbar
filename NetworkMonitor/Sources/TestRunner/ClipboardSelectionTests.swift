import Foundation
import NetworkMonitorUI

// MARK: - 卡片多选变换（单击 / ⌘ / ⇧ / ⌘A / 清空）

/// 多选状态机口径守卫：集合与焦点的不变式、三种点击语义、全选与清空
///
/// 焦点与集合的关系是这一层的核心约束：焦点永远是「方向键与详情区的落点」，
/// 因此它必须在选中集合内（集合非空时），否则详情区会显示一条未选中的条目。
func runClipboardSelectionTests() {
    print("🧪 Testing clipboard multi-selection...")

    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    let visible = [a, b, c, d]

    // 1) 无修饰键单击：替换为单条，焦点跟着走
    var model = ClipboardSelectionModel()
    model.click(c, click: .replace, visibleIDs: visible)
    assertEqual(model.ids, [c], "单击替换选中为单条")
    assertEqual(model.focusedID, c, "单击后焦点落在该条")
    assertEqual(model.isMultiSelecting, false, "单条选中不算多选")

    // 2) ⌘ 单击：追加，不改已有选中
    model.click(a, click: .toggle, visibleIDs: visible)
    assertEqual(model.ids, [a, c], "⌘ 单击追加一条")
    assertEqual(model.isMultiSelecting, true, "两条即多选")
    assertEqual(model.focusedID, a, "⌘ 单击把焦点移到新加的那条")

    // 3) ⌘ 再点同一条：取消该条，焦点回落到剩余选中项
    model.click(a, click: .toggle, visibleIDs: visible)
    assertEqual(model.ids, [c], "⌘ 再点取消该条")
    assertEqual(model.focusedID, c, "焦点回落到剩余选中项")

    // 4) ⇧ 单击：从焦点扩展到目标（含两端）
    model = ClipboardSelectionModel()
    model.click(a, click: .replace, visibleIDs: visible)
    model.click(c, click: .extend, visibleIDs: visible)
    assertEqual(model.ids, [a, b, c], "⇧ 从焦点向后范围选（含两端）")
    assertEqual(model.focusedID, a, "⇧ 范围选后锚点不变")

    // 5) ⇧ 反向：锚点在后、目标在前，集合顺序无关
    model = ClipboardSelectionModel()
    model.click(d, click: .replace, visibleIDs: visible)
    model.click(b, click: .extend, visibleIDs: visible)
    assertEqual(model.ids, [b, c, d], "⇧ 从焦点向前范围选")
    assertEqual(model.focusedID, d, "反向范围选锚点仍不变")

    // 6) ⇧ 无锚点时退化为替换（不会空手而归）
    model = ClipboardSelectionModel()
    model.click(b, click: .extend, visibleIDs: visible)
    assertEqual(model.ids, [b], "无焦点时 ⇧ 单击退化为替换")
    assertEqual(model.focusedID, b, "退化后焦点落在该条")

    // 7) ⌘A 全选：集合 = 全部可见项，焦点落第一条
    model = ClipboardSelectionModel()
    model.selectAll(visibleIDs: visible)
    assertEqual(model.ids, Set(visible), "⌘A 选中全部可见条目")
    assertEqual(model.count, 4, "⌘A 后条数等于可见条数")
    assertEqual(model.focusedID, a, "⌘A 后焦点落在第一条")

    // 8) 清空：集合与焦点一起归零
    model.clear()
    assertEqual(model.ids.isEmpty, true, "清空后集合为空")
    assertEqual(model.focusedID, nil, "清空后无焦点")
    assertEqual(model.isMultiSelecting, false, "清空后不是多选态")

    // 9) 不可见条目点击被忽略（不把过滤掉的行塞进集合）
    model = ClipboardSelectionModel()
    model.click(UUID(), click: .replace, visibleIDs: visible)
    assertEqual(model.ids.isEmpty, true, "点击不可见条目不改集合")
    assertEqual(model.focusedID, nil, "点击不可见条目不留焦点")

    // 10) 过滤裁剪：丢掉不可见选中项，焦点回落到存活项
    model = ClipboardSelectionModel()
    model.selectAll(visibleIDs: visible)
    model.prune(visibleIDs: [c, d])
    assertEqual(model.ids, [c, d], "裁剪后只保留仍可见的选中项")
    assertEqual(model.focusedID, c, "焦点回落到第一个存活项")

    // 11) ⌘A 后 ⌘ 取消当前焦点条：焦点回落到剩余首条，集合仍为多选
    model = ClipboardSelectionModel()
    model.selectAll(visibleIDs: visible)
    model.click(b, click: .toggle, visibleIDs: visible)
    assertEqual(model.ids, Set([a, c, d]), "⌘A 后 ⌘ 取消一条")
    assertEqual(model.focusedID, a, "焦点回落到剩余选中项之首")

    // 12) 方向键焦点移动：选中同步替换为单条
    model = ClipboardSelectionModel()
    model.selectAll(visibleIDs: visible)
    model.focus(b)
    assertEqual(model.ids, [b], "焦点移动把选中替换为单条")
    assertEqual(model.focusedID, b, "焦点落到目标条目")

    print("✅ Clipboard 多选变换 works")
}
