import AppKit
import NetworkMonitorCore

// MARK: - 历史贴到屏幕 / 收藏（从面板控制器拆出，守住单文件门禁）

/// 收藏与贴图同属「把一条历史固定住」的语义，共用 .pin 音效。
extension ClipboardPanelController {

    func panelView(_ view: ClipboardPanelView, didRequestPinAt index: Int) {
        guard filteredItems.indices.contains(index) else { return }
        let item = filteredItems[index]
        guard let onRequestPin else {
            logger.warning("未接线贴图链路，无法把历史贴到屏幕")
            return
        }
        hide(animated: true)
        // 贴到屏幕与收藏同属「固定住」的语义，共用 .pin 音效（设计规格 §3 B3 的 cue 定义）
        feedback.sound.play(.pin)
        onRequestPin(item)
    }

    /// ⌘D：收藏 / 取消收藏当前选中项
    func togglePin() {
        guard let item = selectedItem else { return }
        setPinned(!item.isPinned, for: item, keepingSelection: item.id)
    }

    /// 收藏切换的唯一实现：⌘D（作用在选中项）与星标单击（作用在点中的那条）共用
    ///
    /// - Parameters:
    ///   - pinned: 目标状态（true = 收藏）
    ///   - item: 被操作的条目
    ///   - keepingSelection: 重载后要保住的选中项；点星标时不改选中态，传当前选中项即可
    private func setPinned(_ pinned: Bool, for item: ClipboardItem, keepingSelection preferredID: UUID?) {
        repository.setClipboardItemPinned(id: item.id, isPinned: pinned)
        // 反馈只在此处打一次：卡片刷新只重建视图，不再重复触发
        reportPinToggled(to: pinned)
        AppEvents.postClipboardChanged()
        reloadItems(preferredID: preferredID)
    }

    /// 星标单击：切收藏，不动选中态（用户点星是想收藏，不是想换当前条）
    func panelView(_ view: ClipboardPanelView, didRequestTogglePinAt index: Int) {
        guard filteredItems.indices.contains(index) else { return }
        let item = filteredItems[index]
        setPinned(!item.isPinned, for: item, keepingSelection: selectedItem?.id ?? item.id)
    }
}
