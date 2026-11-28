import Foundation
import NetworkMonitorUI

// MARK: - 板标签行布局与切板过滤（纯函数）

/// 板标签行的守门测试 —— 钉住三件事：标签行永不溢出可用宽、「＋」新建永远在、
/// 以及「全部 = 不过滤 / 选中板 = 只留该板」的切板口径与 ⌘←/→ 的环回。
func runClipboardBoardRowTests() {
    print("🧪 Testing clipboard board row (layout + filter + cycle)...")

    // MARK: 布局

    let chips = [
        ClipboardBoardRow.Chip(id: "all", label: "全部", colorIndex: nil, width: 46),
        ClipboardBoardRow.Chip(id: "b1", label: "工作", colorIndex: 0, width: 58),
        ClipboardBoardRow.Chip(id: "b2", label: "资料", colorIndex: 1, width: 58),
    ]
    let wide = ClipboardBoardRow.layout(chips: chips, originX: 10, rowY: 32, available: 620)
    assertEqual(wide.chips.count, 3, "宽裕时三枚标签都排下")
    assertEqual(wide.isTruncated, false, "排得下就不出现「+N」徽标")
    assertEqual(wide.addButton.minX, wide.chips[2].frame.maxX + ClipboardBoardRow.chipGap,
                "「＋」紧跟最后一枚标签（不飘到行右端）")
    assertEqual(wide.addButton.width, ClipboardBoardRow.addButtonWidth, "「＋」定宽")
    assertEqual(wide.chips[1].frame.minX, wide.chips[0].frame.maxX + ClipboardBoardRow.chipGap,
                "标签之间只隔一个间距")
    assertEqual(wide.chips[0].frame.midY, wide.addButton.midY, "标签与「＋」同一纵向中线")
    assertEqual(wide.chips[0].frame.midY, 32 + ClipboardPanelLayout.toolbarHeight / 2,
                "标签在工具条行内垂直居中")
    assertEqual(wide.rightEdge <= 10 + 620, true, "标签行不溢出可用宽")

    // 序号与色点：第一枚「全部」不带色点
    assertEqual(wide.chips[0].colorIndex == nil, true, "「全部」不画色点")
    assertEqual(wide.chips[1].colorIndex, 0, "板标签带自己的色板下标")

    // 行高可覆盖：胶囊在传入的行高里垂直居中（工具条 34pt 与独立行同一口径）
    let inBar = ClipboardBoardRow.layout(chips: chips, originX: 10, rowY: 0,
                                         available: 620, rowHeight: 34)
    assertEqual(inBar.chips[0].frame.midY, 34 / 2, "胶囊在 34pt 工具条行内居中")

    // 挤的时候：排下 + 徽标里的 = 全部，且「＋」仍在
    let many = (0..<10).map { index in
        ClipboardBoardRow.Chip(id: "b\(index)", label: "板\(index)", colorIndex: index % 8, width: 70)
    }
    let crowded = ClipboardBoardRow.layout(chips: many, originX: 10, rowY: 32, available: 240)
    let hidden = Int(crowded.overflow?.label.dropFirst() ?? "0") ?? 0
    assertEqual(crowded.chips.count + hidden, many.count, "排下的 + 徽标里的 = 全部标签（不静默丢）")
    assertEqual(crowded.addButton.width, ClipboardBoardRow.addButtonWidth, "挤的时候「＋」仍在")
    assertEqual(crowded.rightEdge <= 10 + 240, true, "挤的时候也不溢出")

    // 可用宽 0：整行让位
    let collapsed = ClipboardBoardRow.layout(chips: many, originX: 10, rowY: 32, available: 0)
    assertEqual(collapsed.isVisible, false, "可用宽 0 时整行让位")
    assertEqual(collapsed.chips.isEmpty, true, "让位时一枚标签都不画")

    // 标签宽 = 文字宽 + 内边距 + 色点占位
    let withDot = ClipboardBoardRow.chipWidth(textWidth: 30, hasDot: true)
    let noDot = ClipboardBoardRow.chipWidth(textWidth: 30, hasDot: false)
    assertEqual(withDot - noDot, ClipboardBoardRow.dotSize + ClipboardBoardRow.dotGap,
                "带色点的标签多一个色点占位")
    assertEqual(noDot, 30 + ClipboardBoardRow.chipPaddingX * 2, "不带色点时只有内边距")

    // MARK: 切板过滤

    let boardA = UUID(), boardB = UUID()
    assertEqual(ClipboardBoardFilter.matches(itemBoardID: boardA, selected: nil), true,
                "「全部」= 不过滤，板内项也显示")
    assertEqual(ClipboardBoardFilter.matches(itemBoardID: nil, selected: nil), true,
                "「全部」= 不过滤，未归类项也显示")
    assertEqual(ClipboardBoardFilter.matches(itemBoardID: boardA, selected: boardA), true,
                "选中 A 板时 A 板条目保留")
    assertEqual(ClipboardBoardFilter.matches(itemBoardID: boardA, selected: boardB), false,
                "选中 B 板时 A 板条目被过滤")
    assertEqual(ClipboardBoardFilter.matches(itemBoardID: nil, selected: boardA), false,
                "选中某板后未归类条目不出现")

    // MARK: ⌘← / ⌘→ 环回

    let ids = [boardA, boardB]
    assertEqual(ClipboardBoardCycle.next(current: nil, boardIDs: ids, step: 1), boardA,
                "全部 → 右 → 第一块板")
    assertEqual(ClipboardBoardCycle.next(current: boardA, boardIDs: ids, step: 1), boardB,
                "第一块 → 右 → 第二块")
    assertEqual(ClipboardBoardCycle.next(current: boardB, boardIDs: ids, step: 1) == nil, true,
                "最后一块 → 右 → 回到「全部」（环回）")
    assertEqual(ClipboardBoardCycle.next(current: nil, boardIDs: ids, step: -1), boardB,
                "全部 → 左 → 最后一块（反向环回）")
    assertEqual(ClipboardBoardCycle.next(current: boardA, boardIDs: ids, step: -1) == nil, true,
                "第一块 → 左 → 「全部」")
    assertEqual(ClipboardBoardCycle.next(current: boardA, boardIDs: [], step: 1), boardA,
                "没有板时原地不动")
    assertEqual(ClipboardBoardCycle.next(current: boardA, boardIDs: ids, step: 0), boardA,
                "步长 0 不变")

    print("✅ Clipboard board row (layout + filter + cycle) works")
}
