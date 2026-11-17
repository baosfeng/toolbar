import Foundation
import NetworkMonitorUI

// MARK: - 剪贴板工具条列宽分配（芯片行 + 弹性搜索框）

/// 工具条横向分配的守门测试 —— 从详情区分段测试拆出（原文件触到单文件 15 KiB 上限）
///
/// 钉住三件事：芯片行永不溢出可用宽、搜索框永不被压到下限以下、
/// 芯片多时收进「+N」徽标而不是压缩搜索框或挤掉「＋筛选」按钮。
func runClipboardToolbarLayoutTests() {
    print("🧪 Testing clipboard toolbar layout (chip row + elastic search)...")
    do {
        // MARK: 工具条列宽分配（芯片行 + 弹性搜索框）

        let wideToolbar = ClipboardPanelLayout.toolbarMetrics(width: 1200, captureWidth: 118)
        assertEqual(wideToolbar.search.width, ClipboardPanelLayout.searchMaxWidth,
                    "面板够宽时搜索框取上限 420，不再继续变宽")
        assertEqual(wideToolbar.capture.maxX, 1200 - ClipboardPanelLayout.paddingX, "采集按钮贴右内边距")

        // 无芯片：搜索框贴左内边距，后面只剩「＋筛选」按钮
        let toolbar = ClipboardPanelLayout.toolbarMetrics(width: 640, captureWidth: 118)
        assertEqual(toolbar.search.minX, ClipboardPanelLayout.paddingX + ClipboardFilterChipRow.menuButtonWidth
                    + ClipboardFilterChipRow.searchGap, "无芯片时搜索框紧跟「＋筛选」按钮")
        assertEqual(toolbar.chipRow.menuButton.minX, ClipboardPanelLayout.paddingX, "「＋筛选」贴左内边距")
        assertEqual(toolbar.chipRow.chips.isEmpty, true, "没有筛选时芯片行是空的")
        assertEqual(toolbar.capture.maxX, 640 - ClipboardPanelLayout.paddingX, "采集按钮贴右内边距")
        assertEqual(toolbar.help.maxX, toolbar.capture.minX - ClipboardPanelLayout.toolbarGap,
                    "「?」在采集按钮左侧一个间距处")
        assertEqual(toolbar.help.width, ClipboardPanelLayout.helpButtonWidth, "「?」固定宽 24")
        assertEqual(toolbar.search.midY, toolbar.capture.midY, "工具条各控件同一纵向中线")
        assertEqual(toolbar.capture.height, ClipboardPanelLayout.toolbarControlHeight, "工具条控件高 24")
        assertEqual(toolbar.search.width, ClipboardPanelLayout.searchMaxWidth,
                    "过滤搬进搜索行后 640pt 下搜索框取到上限 420（原先被 160pt 分段控件占住）")

        // 窄面板 480：芯片行整行让位（宁可没有筛选入口），搜索框仍不被压到下限以下、也不溢出面板
        let narrowToolbar = ClipboardPanelLayout.toolbarMetrics(width: 480, captureWidth: 118)
        assertEqual(narrowToolbar.chipRow.isVisible, false, "480pt 下芯片行让位")
        assertEqual(narrowToolbar.search.minX, ClipboardPanelLayout.paddingX, "让位后搜索框回到左内边距")
        assertEqual(narrowToolbar.search.width >= ClipboardPanelLayout.searchMinWidth, true,
                    "窄面板下搜索框不低于下限 300")
        assertEqual(narrowToolbar.search.maxX <= narrowToolbar.help.minX - ClipboardPanelLayout.toolbarGap, true,
                    "搜索框不压到「?」按钮（不溢出可用宽）")
        assertEqual(narrowToolbar.help.maxX, narrowToolbar.capture.minX - ClipboardPanelLayout.toolbarGap,
                    "窄面板下「?」仍在采集左侧")

        // 带芯片：搜索框右移，且仍不低于下限；芯片行永不越过「?」左侧的可用宽
        let chips = [ClipboardFilterChipRow.Chip(id: "source:Safari", label: "Safari", width: 74),
                     ClipboardFilterChipRow.Chip(id: "date:today", label: "今天", width: 52)]
        let chipToolbar = ClipboardPanelLayout.toolbarMetrics(width: 760, captureWidth: 118, chips: chips)
        assertEqual(chipToolbar.chipRow.chips.count, 2, "760pt 下两枚芯片都排得下")
        assertEqual(chipToolbar.chipRow.isTruncated, false, "排得下就不出现「+N」徽标")
        assertEqual(chipToolbar.chipRow.rightEdge <= chipToolbar.help.minX - ClipboardPanelLayout.toolbarGap, true,
                    "芯片行 +「＋筛选」不越过「?」左侧的可用宽")
        assertEqual(chipToolbar.search.minX, chipToolbar.chipRow.rightEdge + ClipboardFilterChipRow.searchGap,
                    "搜索框紧跟芯片行右边缘一个间距")
        assertEqual(chipToolbar.search.width >= ClipboardPanelLayout.searchMinWidth, true,
                    "带芯片时搜索框仍不低于下限（宽面板）")

        // MARK: 芯片行排版（省略与「+N」徽标）

        let manyChips = (0..<8).map { index in
            ClipboardFilterChipRow.Chip(id: "source:App\(index)", label: "App\(index)", width: 80)
        }
        let crowded = ClipboardFilterChipRow.layout(chips: manyChips, originX: ClipboardPanelLayout.paddingX,
                                                    y: 0, available: 200)
        assertEqual(crowded.chips.isEmpty, false, "挤的时候仍先排下能排的芯片")
        let hiddenInBadge = Int(crowded.overflow?.label.dropFirst() ?? "0") ?? 0
        assertEqual(crowded.chips.count + hiddenInBadge, manyChips.count,
                    "排下的 + 徽标里的 = 全部芯片（不静默丢）")
        assertEqual(crowded.rightEdge <= ClipboardPanelLayout.paddingX + 200, true, "芯片行不溢出可用宽")
        assertEqual(crowded.menuButton.width, ClipboardFilterChipRow.menuButtonWidth, "「＋筛选」永远在")

        // 可用宽 0（窄面板让位）：整行不出现，右边缘退回起点
        let collapsed = ClipboardFilterChipRow.layout(chips: manyChips, originX: ClipboardPanelLayout.paddingX,
                                                      y: 0, available: 0)
        assertEqual(collapsed.isVisible, false, "可用宽 0 时芯片行整行让位")
        assertEqual(collapsed.rightEdge, ClipboardPanelLayout.paddingX, "让位后右边缘退回起点")
        assertEqual(collapsed.chips.isEmpty, true, "让位时一枚芯片都不画")

        // 空芯片 + 有预算：只有「＋筛选」按钮
        let emptyChips = ClipboardFilterChipRow.layout(chips: [], originX: ClipboardPanelLayout.paddingX,
                                                       y: 0, available: 200)
        assertEqual(emptyChips.chips.isEmpty, true, "没有芯片时行内无芯片")
        assertEqual(emptyChips.isTruncated, false, "没有芯片时不会出现徽标")
        assertEqual(emptyChips.menuButton.minX, ClipboardPanelLayout.paddingX, "没有芯片时按钮贴起点")
        assertEqual(emptyChips.chips.allSatisfy { $0.frame.width > 0 }, true, "排下的芯片都有正宽")

        // 放得下就不省略：两枚芯片按传入顺序从左往右排
        let roomy = ClipboardFilterChipRow.layout(chips: chips, originX: ClipboardPanelLayout.paddingX,
                                                  y: 0, available: 400)
        assertEqual(roomy.chips.count, 2, "宽裕时两枚芯片都排下")
        assertEqual(roomy.isTruncated, false, "宽裕时不出现徽标")
        assertEqual(roomy.chips[1].frame.minX, roomy.chips[0].frame.maxX + ClipboardFilterChipRow.chipGap,
                    "芯片之间只隔一个间距")
        assertEqual(roomy.menuButton.minX, roomy.chips[1].frame.maxX + ClipboardFilterChipRow.chipGap,
                    "「＋筛选」紧跟最后一枚芯片")

        print("✅ Clipboard toolbar layout (chip row + elastic search) works")
    }
}
