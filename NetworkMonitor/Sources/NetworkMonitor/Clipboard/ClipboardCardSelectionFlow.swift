import AppKit
import NetworkMonitorCore

// MARK: - 卡片流的多选渲染

/// 卡片流的多选口径 —— 独立成文件而不是继续堆进 `ClipboardCardFlowView+…`：
/// 同族门禁按类名前缀聚合行数且只允许变小，多选是新领域，落进新族才不撑大既有族。
///
/// 与单条渲染的分工：单条只关心「焦点是谁」，多选还要关心「还有谁被选中」，
/// 因此选中态在这里按集合下发，卡片流只负责把集合摊到窗口内的每张卡上。
extension ClipboardCardFlowView {

    /// 单条口径的选中集合（快照 / 预览等只给下标的老调用点用）
    static func singleSelection(items: [ClipboardItem], index: Int) -> Set<UUID> {
        guard index >= 0, index < items.count else { return [] }
        return [items[index].id]
    }

    /// 是否处于多选态（⌘N 角标据此隐藏）
    var isMultiSelecting: Bool { selectedIDs.count > 1 }

    /// 重建卡片流并按集合落选中态
    ///
    /// 单条删除仍先播删除动效（0.15s 缩小 + 淡出）再重排：动效期间到达的渲染只排队。
    func render(items: [ClipboardItem], selectedIndex: Int, selectedIDs: Set<UUID>) {
        let removed = isPlayingRemoval ? [] : vanishedCards(newItems: items)
        let vanished = (removed.count == 1 && items.count == self.items.count - 1) ? removed : []
        guard vanished.isEmpty else {
            stageRender(items: items, selectedIndex: selectedIndex, selectedIDs: selectedIDs)
            playRemoval(on: vanished) { [weak self] in
                guard let self else { return }
                self.finishStagedRender()
            }
            return
        }
        apply(items: items, selectedIndex: selectedIndex, selectedIDs: selectedIDs)
    }

    /// 仅切换选中态（焦点卡驱动滑动窗口；多选时其余卡片同步高亮）
    func updateSelection(_ index: Int, selectedIDs: Set<UUID>) {
        self.selectedIDs = selectedIDs
        guard index >= 0, index < items.count else {
            // 逐条取消到空：没有焦点也要把卡片选中态清干净（窗口不动）
            syncCards(); layoutCards(); refreshShadows()
            return
        }
        let previous = selectedIndex
        selectedIndex = index
        slideWindow(force: false)
        syncCards()
        layoutCards()
        scrollToSelection()
        if previous != selectedIndex { onSelectionChanged?() }
        refreshShadows()
    }
}
