import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片交互（命中 / hover 提亮）

/// `ClipboardCardView` 的鼠标交互 —— 自绘后卡内没有子视图，命中判定由本文件重做
///
/// 命中口径在 `ClipboardCardHitTest`（纯函数，TestRunner 覆盖）：星标 / 角标 / 正文 / meta
/// 都是整卡的一部分，单击一律选中、双击一律粘贴、右键一律弹菜单——与改造前 8 个子视图
/// 全部 `hitTest → self` 的行为等价，区别只是现在不需要再靠视图树把事件「捞」回卡片。
///
/// hover 只做视觉反馈（提亮 + 描边）：详情区常驻在面板底部，悬停不再弹任何浮层，
/// 因此也不需要计时器与「移出即收」的接线。
extension ClipboardCardView {

    // MARK: 命中

    /// 点所在的卡片区域（flipped 坐标）
    func hitRegion(at point: CGPoint) -> ClipboardCardHitRegion {
        ClipboardCardHitTest.region(at: point,
                                    in: bounds,
                                    badgeSize: badgeSize,
                                    isImage: item?.kind == .image)
    }

    /// 非激活面板的首次点击必须由视图放行（面板打开即列卡片，用户第一次点就该生效）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 按下只做两件事：记拖拽起点、按修饰键改选中集合
    ///
    /// 粘贴延迟到 mouseUp（见 ClipboardCardDrag）：按下就贴的话，用户按下去想拖一下会先被粘走；
    /// mouseUp 用「起拖时已清空 pressAnchor」区分点击与拖拽。⌘/⇧ 是选择意图，不粘贴。
    override func mouseDown(with event: NSEvent) {
        pressAnchor = convert(event.locationInWindow, from: nil)
        let region = hitRegion(at: pressAnchor ?? .zero)
        let action = ClipboardCardHitTest.action(for: region,
                                                 clickCount: event.clickCount,
                                                 isContextMenu: false)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let click: ClipboardSelectionModel.Click = flags.contains(.shift)
            ? .extend
            : (flags.contains(.command) ? .toggle : .replace)
        if action == .select || action == .paste { onClickWithModifiers?(self, click) }
        // 双击的第二次按下不再粘贴：第一次 mouseUp 已经粘过，面板此时正在收起
        if event.clickCount >= 2 { pressAnchor = nil }
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
        applyHover(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        cancelHover()
    }

    /// 移出卡片 / 播放删除动效时收起 hover 态（只改视觉，不涉及其它视图）
    func cancelHover() {
        applyHover(false, animated: true)
    }
}