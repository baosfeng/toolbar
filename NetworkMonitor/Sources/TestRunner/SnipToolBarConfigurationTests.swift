import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 截图工具条配置（文字提示档 / 组顺序 / 组显隐 / 常驻工具 / 动作显隐）

func runSnipToolBarConfigurationTests() {
    print("🧪 Testing snip toolbar configuration...")

    // 默认配置：悬停提示档、四组全显示、四个高频工具常驻、四个动作按钮
    let standard = SnipToolBarConfiguration.standard
    assertEqual(standard.labelMode, SnipToolBarLabelMode.hover, "默认走悬停提示（对齐 Snipaste）")
    assertEqual(standard.groupOrder, SnipToolBarGroup.allCases, "默认组顺序即 allCases 顺序")
    assertEqual(standard.visibleGroups, Set(SnipToolBarGroup.allCases), "默认四组都显示")
    assertEqual(standard.primaryTools, SnipTool.primary, "默认常驻工具沿用 SnipTool.primary")
    assertEqual(standard.visibleActions, SnipBarAction.allCases, "默认四个动作按钮全显示")
    assertEqual(standard.placement, SnipToolBarPlacement.auto, "默认位置档为自动")
    assertEqual(standard.overflowTools.count, SnipTool.allCases.count - SnipTool.primary.count,
                "溢出工具 = 全部工具减去常驻工具")
    assertEqual(standard.orderedVisibleGroups.count, 4, "默认显示四组")

    // 计数与布局同源：隐藏颜色 / 线宽后这两组按钮数为 0，工具组不受影响
    var noColor = standard
    noColor.visibleGroups = [.tools, .actions]
    assertEqual(noColor.colorGroupCount, 0, "隐藏颜色组后颜色按钮数为 0")
    assertEqual(noColor.widthGroupCount, 0, "隐藏线宽组后线宽按钮数为 0")
    assertEqual(noColor.toolGroupCount, SnipTool.primary.count + 1, "工具组 = 常驻工具 + 更多入口")
    assertEqual(noColor.actionGroupCount, SnipBarAction.allCases.count, "动作组按钮数不变")

    // 常驻工具排满十个时没有「更多」入口：工具组计数随之减少
    var allTools = standard
    allTools.primaryTools = SnipTool.allCases
    assertEqual(allTools.overflowTools.count, 0, "全部常驻时没有溢出工具")
    assertEqual(allTools.toolGroupCount, SnipTool.allCases.count, "全部常驻时工具组不带「更多」")

    // 非法输入整理：空可见组回落全显示，空工具回落默认四个，空动作回落「复制」
    let emptyGroups = SnipToolBarConfiguration(visibleGroups: [])
    assertEqual(emptyGroups.visibleGroups, Set(SnipToolBarGroup.allCases), "可见组为空时回落全显示")
    let emptyTools = SnipToolBarConfiguration(primaryTools: [])
    assertEqual(emptyTools.primaryTools, SnipTool.primary, "常驻工具为空时回落默认四个")
    let emptyActions = SnipToolBarConfiguration(visibleActions: [])
    assertEqual(emptyActions.visibleActions, [SnipBarAction.copy], "动作全关时保留复制，保证有输出出口")

    // 常驻工具保持配置里的顺序、只去重：用户新选的工具追加到最右，不让按钮跳位
    let shuffledTools = SnipToolBarConfiguration(primaryTools: [.text, .rectangle, .text])
    assertEqual(shuffledTools.primaryTools, [.text, .rectangle], "常驻工具保持配置顺序并去重")
    let shuffledActions = SnipToolBarConfiguration(visibleActions: [.cancel, .copy, .copy])
    assertEqual(shuffledActions.visibleActions, [.cancel, .copy], "动作按钮保持配置顺序并去重")

    // 组顺序整理：未知组名丢弃、缺失组补到末尾、重复只留一个
    let order = SnipToolBarGroup.order(from: ["actions", "unknown", "tools", "actions"])
    assertEqual(order, [.actions, .tools, .color, .width], "组顺序去未知去重并补齐缺失项")
    let reordered = SnipToolBarConfiguration(groupOrder: [.actions, .tools, .color, .width])
    assertEqual(reordered.orderedVisibleGroups, [.actions, .tools, .color, .width],
                "重新排序后 orderedVisibleGroups 跟着变")

    // 文字提示档：只有常驻标签档会加高工具条
    assertEqual(SnipToolBarLabelMode.hover.showsPersistentLabel, false, "悬停档不加高工具条")
    assertEqual(SnipToolBarLabelMode.always.showsPersistentLabel, true, "常驻标签档加高工具条")
    assertEqual(SnipToolBarLabelMode.hover.showsHoverBubble, true, "悬停档要气泡")
    assertEqual(SnipToolBarLabelMode.iconOnly.showsHoverBubble, false, "仅图标档不弹气泡")

    // MARK: 布局按配置出宽度

    // 隐藏颜色与线宽后整条更窄（两组各去掉按钮 + 一段组间带）
    let fullWidth = SnipToolBarLayout.plan(config: standard).width
    let trimmedWidth = SnipToolBarLayout.plan(config: noColor).width
    assertEqual(trimmedWidth < fullWidth, true, "隐藏两组后工具条变窄")
    let expectedShrink = SnipToolBarLayout.colorSide + SnipToolBarLayout.widthSide
                        + SnipToolBarLayout.groupGap * 2
    assertEqual(fullWidth - trimmedWidth, expectedShrink,
                "收窄的量 = 两组按钮宽 + 两段组间带")

    // 左右内边距在任何配置下都恒等（回归：右侧曾多出 17pt）
    for config in [standard, noColor, allTools, emptyGroups] {
        let plan = SnipToolBarLayout.plan(config: config)
        let firstX = plan.toolRects.first?.minX ?? -1
        let lastMaxX = (plan.actionRects.last ?? plan.widthRects.last ?? plan.colorRects.last
                        ?? plan.toolRects.last)?.maxX ?? 0
        assertEqual(plan.width - lastMaxX, SnipToolBarLayout.padding,
                    "右侧内边距恒等于 padding")
        if firstX >= 0 {
            assertEqual(firstX, SnipToolBarLayout.padding, "左侧内边距恒等于 padding")
        }
    }

    // 组顺序变化：分隔线数量跟可见组数走，且 groupRects 按顺序给出
    let swapped = SnipToolBarLayout.plan(config: reordered)
    assertEqual(swapped.orderedGroups, [.actions, .tools, .color, .width],
                "plan 的组顺序与配置一致")
    assertEqual(swapped.dividerXs.count, 3, "四组之间三条分隔线")
    assertEqual(swapped.dividerXs, swapped.dividerXs.sorted(), "分隔线 x 单调递增")

    // 只留工具组：一条分隔线都没有，整条工具条不存在空转
    let onlyTools = SnipToolBarLayout.plan(config: SnipToolBarConfiguration(visibleGroups: [.tools]))
    assertEqual(onlyTools.dividerXs.count, 0, "只剩一组时不发分隔线")
    assertEqual(onlyTools.actionRects.count, 0, "隐藏动作组时无动作按钮矩形")

    // 文字提示档决定条高：悬停 / 仅图标 40pt，常驻标签 50pt；悬停档额外留气泡区
    assertEqual(SnipToolBarLayout.barHeight(for: .iconOnly), 40, "仅图标档条高 40pt")
    assertEqual(SnipToolBarLayout.barHeight(for: .hover), 40, "悬停档条高不变（气泡画在条外）")
    assertEqual(SnipToolBarLayout.barHeight(for: .always), 50, "常驻标签档条高 50pt")
    assertEqual(SnipToolBarLayout.outerHeight(for: .hover),
                SnipToolBarLayout.height + SnipToolBarLayout.bubbleSpace,
                "悬停档视图高度 = 条高 + 气泡区")
    assertEqual(SnipToolBarLayout.outerHeight(for: .always), 50,
                "常驻标签档不需要气泡区")

    // 常驻标签档按钮更宽更高，整条随之变宽（标签要放得下中文名）
    let labeledPlan = SnipToolBarLayout.plan(config: SnipToolBarConfiguration(labelMode: .always))
    assertEqual(labeledPlan.toolRects.first?.width, SnipToolBarLayout.labeledMetrics.tool.width,
                "常驻标签档工具按钮更宽")
    assertEqual(labeledPlan.height, 50, "常驻标签档条高 50pt")

    // MARK: 偏好解析

    // 缺键回落默认配置（读路径不写回：存不存在的判据交给调用方）
    let blank = SnipToolBarConfigurationResolver.resolve(labelModeRaw: nil,
                                                         groupOrderRaw: nil,
                                                         hiddenGroupsRaw: nil,
                                                         primaryToolsRaw: nil,
                                                         hiddenActionsRaw: nil)
    assertEqual(blank, standardsForResolver(), "全部缺键时解析出默认配置")

    // 未知档位回落悬停；非法组名丢弃但补齐；隐藏动作按串生效
    let resolved = SnipToolBarConfigurationResolver.resolve(
        labelModeRaw: "unknown",
        groupOrderRaw: "width,color",
        hiddenGroupsRaw: "tools",
        primaryToolsRaw: "text,rectangle,bogus",
        hiddenActionsRaw: "pin,save")
    assertEqual(resolved.labelMode, .hover, "未知档位回落悬停提示")
    assertEqual(resolved.groupOrder, [.width, .color, .tools, .actions], "组顺序补齐缺失项")
    assertEqual(resolved.visibleGroups, [.color, .width, .actions], "隐藏组按串生效")
    assertEqual(resolved.primaryTools, [.text, .rectangle], "常驻工具丢弃非法名并保持存储顺序")
    assertEqual(resolved.visibleActions, [.cancel, .copy], "隐藏动作按串生效")

    // 存储往返：persist 写五个键，load 读回来与原配置一致
    let storage = InMemoryStorage()
    let roundTrip = SnipToolBarConfiguration(labelMode: .always,
                                             groupOrder: [.actions, .tools, .color, .width],
                                             visibleGroups: [.tools, .actions],
                                             primaryTools: [.rectangle, .text],
                                             visibleActions: [.copy, .pin])
    SnipToolBarConfigurationResolver.persist(roundTrip, storage: storage)
    let loaded = SnipToolBarConfigurationResolver.load(storage: storage)
    assertEqual(loaded.labelMode, .always, "往返后文字提示档一致")
    assertEqual(loaded.groupOrder, [.actions, .tools, .color, .width], "往返后组顺序一致")
    assertEqual(loaded.visibleGroups, [.tools, .actions], "往返后可见组一致")
    assertEqual(loaded.primaryTools, [.rectangle, .text], "往返后常驻工具一致")
    assertEqual(loaded.visibleActions, [.copy, .pin], "往返后动作按钮一致")
    assertEqual(loaded.placement, .auto, "缺键时位置档回落自动")

    // 位置档往返：显式选「选区上方」后读回来仍是该档
    let placed = SnipToolBarConfiguration(placement: .above)
    SnipToolBarConfigurationResolver.persist(placed, storage: storage)
    assertEqual(SnipToolBarConfigurationResolver.load(storage: storage).placement, .above,
                "位置档往返一致")

    // 列表编码容错：空串 / 多余空格 / 空项
    assertEqual(SnipToolBarListCoding.decode(nil), [], "nil 解码为空列表")
    assertEqual(SnipToolBarListCoding.decode("  "), [], "空白串解码为空列表")
    assertEqual(SnipToolBarListCoding.decode("a, ,b"), ["a", "b"], "空项被丢弃")
    assertEqual(SnipToolBarListCoding.encode(["a", "b"]), "a,b", "编码用逗号连接")

    // MARK: 颜色 / 线宽文案（气泡与面板标签同源）

    assertEqual(SnipAnnotationColorNaming.name(for: .red), "红色", "红色取名正确")
    assertEqual(SnipAnnotationColorNaming.name(for: .blue), "蓝色", "蓝色取名正确")
    let custom = SnipAnnotationColor(red: 0.5, green: 0.2, blue: 0.7)
    assertEqual(SnipAnnotationColorNaming.name(for: custom), "自定义色", "不在调色板时写自定义色")
    assertEqual(SnipAnnotationColorNaming.name(forHex: "#EB3330"), "红色", "hex 取名正确")
    assertEqual(SnipAnnotationColorNaming.name(forHex: nil), "自定义色", "无 hex 时写自定义色")
    // 带透明度的颜色仍按 RGB 认名（调过透明度不该丢名字）
    assertEqual(SnipAnnotationColorNaming.name(for: SnipAnnotationColor(red: 0.92, green: 0.20,
                                                                       blue: 0.19, alpha: 0.6)),
                "红色", "带透明度的红色仍叫红色")

    assertEqual(SnipPanelLabelText.width(4), "4 pt", "整数线宽写作 4 pt")
    assertEqual(SnipPanelLabelText.width(2.5), "2.5 pt", "小数值保留一位")
    assertEqual(SnipPanelLabelText.dash(true), "虚线", "虚线文案")
    assertEqual(SnipPanelLabelText.dash(false), "实线", "实线文案")
    assertEqual(SnipPanelLabelText.alpha(1.0), "不透明", "满透明度文案")
    assertEqual(SnipPanelLabelText.alpha(0.6), "半透明", "半透明文案")
    assertEqual(SnipPanelLabelText.alpha(0.3), "淡", "低透明度文案")

    print("✅ 截图工具条配置测试通过")
}

/// 解析器全部缺键时的期望值（等价于构造一个默认配置）
private func standardsForResolver() -> SnipToolBarConfiguration {
    SnipToolBarConfiguration()
}
