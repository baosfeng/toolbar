import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 多选动作（选中变换 / 全选 / 清空 / 批量删除）

/// 面板控制器的多选动作 —— 独立成文件而不是 `ClipboardPanelController+…`：
/// 同族门禁按类名前缀聚合行数且只允许变小，新领域必须落进新族才能不撑大既有族。
///
/// 状态本体是 `selection`（`ClipboardSelectionModel`，纯逻辑在 NetworkMonitorUI 有断言），
/// 这里只做三件事：把点击 / 键盘事件翻译成状态变换、把状态同步到视图、执行批量删除。
extension ClipboardPanelController {

    /// 当前可见条目 id（顺序 = 卡片顺序，⇧ 范围选与全选都以此为准）
    var visibleIDs: [UUID] { filteredItems.map(\.id) }

    /// 当前选中下标 —— 由焦点派生：多选时焦点就是方向键与详情区的落点
    var selectedIndex: Int {
        guard let focused = selection.focusedID else { return -1 }
        return filteredItems.firstIndex { $0.id == focused } ?? -1
    }

    // MARK: 选中变换

    /// 卡片点击：按修饰键语义改选中集合（无修饰 = 替换、⌘ = 切换、⇧ = 范围选）
    func applySelectionClick(at index: Int, click: ClipboardSelectionModel.Click) {
        guard index >= 0, index < filteredItems.count else { return }
        let id = filteredItems[index].id
        if selection.focusedID != id { cancelEditingOnSelectionChange() }   // 编辑中换条目 = 放弃编辑
        selection.click(id, click: click, visibleIDs: visibleIDs)
        syncSelectionToViews()
        clearDeleteConfirmHint()
    }

    /// 方向键 / ⌘N / 右键菜单：把选中替换为单条并落焦点
    func selectSingle(at index: Int) {
        guard index >= 0, index < filteredItems.count else { return }
        selection.focus(filteredItems[index].id)
        syncSelectionToViews()
        clearDeleteConfirmHint()
    }

    /// ⌘A：全选当前过滤后的可见条目
    func selectAllVisible() {
        guard !filteredItems.isEmpty else { return }
        selection.selectAll(visibleIDs: visibleIDs)
        syncSelectionToViews()
    }

    /// Esc：有多选时收回到焦点单条（返回 true 表示已消费，面板不收起）
    func collapseMultiSelectionIfNeeded() -> Bool {
        guard selection.isMultiSelecting else { return false }
        let anchor = selection.focusedID
        selection.clear()
        if let anchor, filteredItems.contains(where: { $0.id == anchor }) { selection.focus(anchor) }
        syncSelectionToViews()
        return true
    }

    /// 进入编辑态时清空多选：编辑只作用于一条，留着多选会让 ⌘↩ 的落点含混
    func collapseMultiSelectionForEditing() {
        guard selection.isMultiSelecting else { return }
        _ = collapseMultiSelectionIfNeeded()
    }

    /// 过滤 / 重载后恢复选中：优先落到调用方指定的条目，否则裁剪后兜底选第一条
    func restoreSelection(preferredID: UUID?) {
        let visible = filteredItems
        guard !visible.isEmpty else { selection.clear(); return }
        if let preferredID, visible.contains(where: { $0.id == preferredID }) {
            selection.focus(preferredID)
        } else {
            selection.prune(visibleIDs: visible.map(\.id))
        }
        if selection.focusedID == nil { selection.focus(visible[0].id) }
    }

    /// 把状态推给视图：卡片选中集合 + 详情区（多选时换成「已选 N 条」摘要）
    ///
    /// 多选态不刷单条详情：那时详情区没有唯一落点，先刷单条再盖摘要只会多一次重排。
    func syncSelectionToViews() {
        let multi = selection.isMultiSelecting
        content.updateSelection(selectedIndex, item: multi ? nil : selectedItem, selectedIDs: selection.ids)
        if multi { content.updateMultiSelection(count: selection.count) }
    }

    // MARK: 批量删除

    /// ⌘⌫：有多选时删全部选中（返回 true 表示已消费），无多选交回原有单条删除路径
    func requestDeleteMultiSelectionIfNeeded() -> Bool {
        guard selection.isMultiSelecting else { return false }
        let ids = selection.orderedIDs(in: visibleIDs)
        guard !ids.isEmpty else { return false }
        guard multiDeleteConfirm.requestDelete(id: Self.multiDeleteConfirmKey,
                                               now: Date().timeIntervalSince1970) else {
            // 二次确认通过：真正删除
            let doomed = deleteItems(ids: Set(ids))
            finishMultiDelete(deleted: doomed.count)
            return true
        }
        content.showHint(ClipboardMultiSelectionDetail.deleteConfirmHint(count: ids.count))
        return true
    }

    /// 删除后收尾：音效 / 事件 / 重载列表 / 提示条数
    private func finishMultiDelete(deleted: Int) {
        guard deleted > 0 else {
            // 选中的条目已被别的路径删掉：给失败音，不谎报成功
            feedback.sound.play(.error)
            content.showHint("选中的条目已不存在")
            AppEvents.postClipboardChanged()
            reloadItems()
            return
        }
        feedback.sound.play(.delete)
        logger.info("剪贴板批量已删除 \(deleted) 条（二次确认通过）")
        AppEvents.postClipboardChanged()
        selection.clear()
        reloadItems()
        content.showHint(ClipboardMultiSelectionDetail.deletedHint(count: deleted))
    }

    /// 批量删除入口：仓储支持批量能力时走单事务，否则退化为逐条删除（回收口径一致）
    private func deleteItems(ids: Set<UUID>) -> [ClipboardItem] {
        let doomed: [ClipboardItem]
        if let batch = repository as? any ClipboardBatchDeleteRepository {
            doomed = batch.deleteClipboardItems(ids: ids)
        } else {
            doomed = ids.compactMap { repository.deleteClipboardItem(id: $0) }
        }
        // 图片文件随记录一起回收：走的是与单条删除同一个 GC 入口
        ClipboardImageGC.reclaim(items: doomed, logger: logger)
        return doomed
    }

    /// 批量删除确认用的固定标识（状态机标识，与条目 ID 语义无关；与清空历史各持一份）
    static let multiDeleteConfirmKey = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!
}
