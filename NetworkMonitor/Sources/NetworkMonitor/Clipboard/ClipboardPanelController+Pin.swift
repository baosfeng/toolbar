import AppKit
import NetworkMonitorCore

// MARK: - 历史贴到屏幕（从面板控制器拆出，守住单文件门禁）

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
}
