import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片交互（命中 / hover / 全文浮层）

/// `ClipboardCardView` 的鼠标交互 —— 自绘后卡内没有子视图，命中判定由本文件重做
///
/// 命中口径在 `ClipboardCardHitTest`（纯函数，TestRunner 覆盖）：星标 / 角标 / 正文 / meta
/// 都是整卡的一部分，单击一律选中、双击一律粘贴、右键一律弹菜单——与改造前 8 个子视图
/// 全部 `hitTest → self` 的行为等价，区别只是现在不需要再靠视图树把事件「捞」回卡片。
extension ClipboardCardView {

    // MARK: 命中

    /// 点所在的卡片区域（flipped 坐标）
    func hitRegion(at point: CGPoint) -> ClipboardCardHitRegion {
        ClipboardCardHitTest.region(at: point,
                                    in: bounds,
                                    shortcutWidth: shortcutWidth,
                                    badgeSize: badgeSize,
                                    isImage: item?.kind == .image)
    }

    /// 非激活面板的首次点击必须由视图放行（面板打开即列卡片，用户第一次点就该生效）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 单击选中、双击粘贴（与改造前一致：双击同时也会先走一次选中）
    override func mouseDown(with event: NSEvent) {
        let region = hitRegion(at: convert(event.locationInWindow, from: nil))
        let action = ClipboardCardHitTest.action(for: region,
                                                 clickCount: event.clickCount,
                                                 isContextMenu: false)
        if action == .select || action == .paste { onClick?(self) }
        if event.clickCount >= 2 { onDoubleClick?(self) }
    }

    // MARK: hover

    /// 追踪区跟随 bounds（面板滚动 / 复用卡片时重挂）
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isRemoving, !isHovering else { return }
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        cancelHover()
    }

    /// 进入 hover 态：提亮 0.12s 交叉过渡 + 起 0.45s 浮层计时
    ///
    /// 状态推进与过渡都在 applyHover 里（一个入口：改标志、起过渡、重算阴影），本方法只管计时。
    private func setHovering(_ hovering: Bool) {
        applyHover(hovering, animated: true)
        if hovering { scheduleOverlay() }
    }

    /// 悬停满 0.45s 通知外层弹全文浮层（期间移出即取消）
    func scheduleOverlay() {
        hoverTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHovering else { return }
            self.onHoverStateChange?(self, true)
        }
        hoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverOverlayDelay, execute: work)
    }

    /// 移出卡片 / 播放删除动效时收起 hover 态并通知外层收浮层
    func cancelHover() {
        hoverTimer?.cancel()
        hoverTimer = nil
        guard isHovering else { return }
        applyHover(false, animated: true)
        onHoverStateChange?(self, false)
    }
}
