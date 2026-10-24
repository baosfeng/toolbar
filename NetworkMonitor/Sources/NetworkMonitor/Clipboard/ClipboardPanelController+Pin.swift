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
        onRequestPin(item)
    }
}
