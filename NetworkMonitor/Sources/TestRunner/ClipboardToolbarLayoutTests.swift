import Foundation
import NetworkMonitorUI

// MARK: - 剪贴板工具条列宽分配（筛选芯片 + 搜索 + 板胶囊 + 两个图标按钮）

/// 工具条横向分配的守门测试 —— 单行版式（对标 Paste 顶栏一行到底）
///
/// 钉住五件事：
/// 1. 工具条只有一行：筛选芯片 → 搜索框 → 板胶囊 → 计数 →「?」→ 采集图标；
/// 2. 芯片行永不溢出可用宽、搜索框永不被压到下限以下；
/// 3. 板胶囊永远保住「全部 + ＋」的下限，放不下时整节让位而不是画到搜索框上；
/// 4. 两个图标按钮贴右边缘、同一档宽（纯图标 + tooltip）；
/// 5. 条数计数是状态文本，可隐藏、可省略，绝不抢搜索框与板胶囊的位置。
func runClipboardToolbarLayoutTests() {
    print("🧪 Testing clipboard toolbar layout (single row)...")
    do {
        let boards = [
            ClipboardBoardRow.Chip(id: "all", label: "全部", colorIndex: nil, width: 46),
            ClipboardBoardRow.Chip(id: "b1", label: "工作", colorIndex: 0, width: 58),
        ]

        // MARK: 宽面板 1200：搜索框取上限，板胶囊排在搜索框右侧

        let wide = ClipboardPanelLayout.toolbarMetrics(width: 1200, countWidth: 72, boardChips: boards)
        assertEqual(wide.search.width, ClipboardPanelLayout.searchMaxWidth, "面板够宽时搜索框取上限 360")
        assertEqual(wide.capture.maxX, 1200 - ClipboardPanelLayout.paddingX, "采集图标贴右内边距")
        assertEqual(wide.capture.width, ClipboardPanelLayout.iconButtonWidth, "采集图标定宽 24")
        assertEqual(wide.help.maxX, wide.capture.minX - ClipboardPanelLayout.iconGap,
                    "「?」在采集图标左侧一个窄间距处")
        assertEqual(wide.help.width, ClipboardPanelLayout.iconButtonWidth, "「?」与采集同档宽")
        assertEqual(wide.count.maxX, wide.help.minX - ClipboardPanelLayout.toolbarGap,
                    "计数在「?」左侧一个控件间距处")
        assertEqual(wide.count.width, 72, "计数用实测宽（上限 96）")
        assertEqual(wide.boardRow.chips.count, 2, "板胶囊排得下「全部」与各板")
        assertEqual(wide.boardRow.isTruncated, false, "排得下就不出现「+N」徽标")
        assertEqual(wide.boardRow.addButton.width, ClipboardBoardRow.addButtonWidth, "「＋」新建永远在")
        assertEqual(wide.boardRow.chips[0].frame.minX, wide.search.maxX + ClipboardPanelLayout.toolbarGap,
                    "板胶囊紧接搜索框右侧一个间距")
        assertEqual(wide.boardRow.rightEdge <= wide.count.minX, true, "板胶囊不越过计数")

        // MARK: 无芯片：搜索框紧跟「＋筛选」按钮（筛选入口仍在工具条左侧）

        let toolbar = ClipboardPanelLayout.toolbarMetrics(width: 640, countWidth: 72)
        assertEqual(toolbar.chipRow.menuButton.minX, ClipboardPanelLayout.paddingX, "「＋筛选」贴左内边距")
        assertEqual(toolbar.search.minX, ClipboardPanelLayout.paddingX + ClipboardFilterChipRow.menuButtonWidth
                    + ClipboardFilterChipRow.searchGap, "无芯片时搜索框紧跟「＋筛选」按钮")
        assertEqual(toolbar.chipRow.chips.isEmpty, true, "没有筛选时芯片行是空的")
        assertEqual(toolbar.search.midY, toolbar.capture.midY, "工具条各控件同一纵向中线")
        assertEqual(toolbar.capture.height, ClipboardPanelLayout.toolbarControlHeight, "工具条控件高 24")
        assertEqual(toolbar.boardRow.isVisible, true, "640pt 下板胶囊仍有位置（至少「全部 + ＋」）")

        // 计数隐藏时不占位：板胶囊多出一段空间，位置不变（仍在搜索框右侧）
        let noCount = ClipboardPanelLayout.toolbarMetrics(width: 900, countWidth: 0)
        assertEqual(noCount.count.width, 0, "计数隐藏时宽 0")
        assertEqual(noCount.boardRow.isVisible, true, "没有计数时板胶囊照样在")
        assertEqual(noCount.boardRow.rightEdge <= noCount.help.minX - ClipboardPanelLayout.toolbarGap, true,
                    "板胶囊不越过「?」左侧的可用宽")

        // MARK: 窄面板 420：芯片行让位，搜索框不低于下限、板胶囊仍保住下限
        //
        // 480pt 这一档现在仍有芯片行的预算（搜索框 200 + 板标签下限 78 + 按钮 36 都放得下），
        // 让位的门槛落在 420pt 左右 —— 与面板最小宽同档。

        let narrow = ClipboardPanelLayout.toolbarMetrics(width: 420, countWidth: 0, boardChips: boards)
        assertEqual(narrow.chipRow.isVisible, false, "420pt 下筛选芯片行让位")
        assertEqual(narrow.search.minX, ClipboardPanelLayout.paddingX, "让位后搜索框回到左内边距")
        assertEqual(narrow.search.width >= ClipboardPanelLayout.searchMinWidth, true,
                    "窄面板下搜索框不低于下限 200")
        assertEqual(narrow.search.maxX <= narrow.help.minX - ClipboardPanelLayout.toolbarGap, true,
                    "搜索框不压到「?」按钮（不溢出可用宽）")
        assertEqual(narrow.boardRow.addButton.width, ClipboardBoardRow.addButtonWidth,
                    "窄面板下「＋」新建仍未被挤掉")
        assertEqual(narrow.help.maxX, narrow.capture.minX - ClipboardPanelLayout.iconGap,
                    "窄面板下「?」仍在采集左侧")

        // 极窄：板胶囊整节让位（绝不画到搜索框上），搜索框与两个图标仍在
        let tiny = ClipboardPanelLayout.toolbarMetrics(width: 420, countWidth: 0)
        assertEqual(tiny.search.width >= ClipboardPanelLayout.searchMinWidth, true,
                    "420pt 下搜索框仍守住下限")
        assertEqual(tiny.boardRow.addButton.width == 0 || tiny.boardRow.rightEdge <= 420, true,
                    "板胶囊要么让位、要么不溢出面板")

        // MARK: 带芯片：搜索框右移，芯片行不越过板胶囊可用区

        let chips = [ClipboardFilterChipRow.Chip(id: "source:Safari", label: "Safari", width: 74),
                     ClipboardFilterChipRow.Chip(id: "date:today", label: "今天", width: 52)]
        let chipToolbar = ClipboardPanelLayout.toolbarMetrics(width: 760, countWidth: 0, chips: chips)
        assertEqual(chipToolbar.chipRow.chips.count, 2, "760pt 下两枚芯片都排得下")
        assertEqual(chipToolbar.chipRow.isTruncated, false, "排得下就不出现「+N」徽标")
        assertEqual(chipToolbar.chipRow.rightEdge <= chipToolbar.help.minX - ClipboardPanelLayout.toolbarGap, true,
                    "芯片行不越过右侧图标按钮")
        assertEqual(chipToolbar.search.minX, chipToolbar.chipRow.rightEdge + ClipboardFilterChipRow.searchGap,
                    "搜索框紧跟芯片行右边缘一个间距")
        assertEqual(chipToolbar.search.width >= ClipboardPanelLayout.searchMinWidth, true,
                    "带芯片时搜索框仍不低于下限")

        // MARK: 芯片行本身（省略与「+N」徽标）

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

        let collapsed = ClipboardFilterChipRow.layout(chips: manyChips, originX: ClipboardPanelLayout.paddingX,
                                                      y: 0, available: 0)
        assertEqual(collapsed.isVisible, false, "可用宽 0 时芯片行整行让位")
        assertEqual(collapsed.rightEdge, ClipboardPanelLayout.paddingX, "让位后右边缘退回起点")
        assertEqual(collapsed.chips.isEmpty, true, "让位时一枚芯片都不画")

        print("✅ Clipboard toolbar layout (single row) works")
    }
}
