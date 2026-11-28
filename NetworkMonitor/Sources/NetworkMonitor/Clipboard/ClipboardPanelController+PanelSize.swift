import AppKit
import NetworkMonitorUI


extension ClipboardPanelController {

    /// 工具条档位按钮：紧凑 → 标准 → 宽松 循环，写偏好后立即重新定位并重排卡片
    ///
    /// 面板高度变了，卡片尺寸跟着变（卡片尺寸只由卡片区高度推出），故必须重新布局一次；
    /// 展开状态下重算 frame 会触发 didResize，PanelAnchor 的观察者随后补钉顶边。
    func panelViewDidRequestCyclePanelSize(_ view: ClipboardPanelView) {
        let next = ClipboardPanelSize.nearest(to: preferences.panelHeight).next
        preferences.panelHeight = next.height
        view.updatePanelSize(next)
        guard panel.isVisible else { return }
        positionPanel()
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
    }
}
