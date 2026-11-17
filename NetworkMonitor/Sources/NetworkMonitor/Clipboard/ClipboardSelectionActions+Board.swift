import AppKit
import NetworkMonitorCore

// MARK: - 多选 / 单条的「移到板」执行

/// 「移到板…」的执行侧 —— 独立成文件：板移动是新领域，动作体不塞进多选 / 删除那两个既有文件。
///
/// 批量口径：多选时作用于全部选中条目，否则只作用于右键那一条（并把它落成焦点）。
/// 移完统一重载列表与板标签：当前在某块板视图内、被移出的条目会随过滤消失。
extension ClipboardPanelController {

    func panelView(_ view: ClipboardPanelView, didRequestMoveToBoard boardID: UUID?, itemID: UUID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == itemID }) else { return }
        // 多选才批量；单选或右键那条不在选中集合里时，退回只动这一条并把它落成焦点
        let isBatch = selection.isMultiSelecting && selection.ids.contains(itemID)
        if !isBatch { selectSingle(at: index) }
        let ids = isBatch ? selection.orderedIDs(in: visibleIDs) : [itemID]
        guard !ids.isEmpty else { return }
        let moved = boards.move(itemIDs: ids, to: boardID)
        reportBoardMove(moved: moved, requested: ids.count, boardID: boardID)
        AppEvents.postClipboardChanged()
        boards.reload()
        reloadItems(preferredID: itemID)
    }

    /// 移板收尾：音效 + 提示行；一条都没命中时给失败音，不谎报成功
    private func reportBoardMove(moved: Int, requested: Int, boardID: UUID?) {
        let boardName = boardID.flatMap { id in boards.boards.first { $0.id == id }?.name }
        guard moved > 0 else {
            feedback.sound.play(.error)
            content.showHint("没有可移动的条目")
            return
        }
        feedback.sound.play(.pin)
        logger.info("剪贴板移板：\(moved) 条 → \(boardName ?? "移出板")")
        let suffix = moved < requested ? "（\(requested - moved) 条已不在）" : ""
        if let boardName {
            content.showHint(moved > 1 ? "\(moved) 条已移到「\(boardName)」\(suffix)" : "已移到「\(boardName)」\(suffix)")
        } else {
            content.showHint(moved > 1 ? "\(moved) 条已移出板\(suffix)" : "已移出板\(suffix)")
        }
    }
}
