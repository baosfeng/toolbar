import AppKit
import NetworkMonitorUI

// MARK: - 贴图窗内容视图

/// 贴图窗的内容视图：把「左键双击」与「中键单击」从窗口拖动里区分出来
///
/// 官方贴图行为是「左键双击关闭」「中键单击重置为 100% 大小与 100% 不透明」，
/// 但窗口开着 isMovableByWindowBackground，鼠标事件默认被拖动吃掉，双击永远落不到窗口上。
/// 这里先用 PinClickIntent 判出点击语义：双击交给关闭、中键交给重置，
/// 单击与拖动仍走 super（保留「按住任意位置拖窗」的手感）。
@MainActor
final class PinContentView: NSView {

    /// 关闭当前贴图（可恢复）
    var onCloseRequest: (() -> Void)?
    /// 重置为 100% 大小与 100% 不透明
    var onResetRequest: (() -> Void)?

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        switch PinClickIntent.outcome(buttonNumber: event.buttonNumber, clickCount: event.clickCount) {
        case .closeWindow:
            onCloseRequest?()
        case .resetSizeAndAlpha, .dragWindow:
            super.mouseDown(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        switch PinClickIntent.outcome(buttonNumber: event.buttonNumber, clickCount: event.clickCount) {
        case .resetSizeAndAlpha:
            onResetRequest?()
        case .closeWindow, .dragWindow:
            super.otherMouseDown(with: event)
        }
    }
}
