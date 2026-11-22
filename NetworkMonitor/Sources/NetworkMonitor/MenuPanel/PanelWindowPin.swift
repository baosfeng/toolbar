import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板窗口横向钉住

/// 把面板窗口横向钉在「展开那一刻的状态项右边缘」上
///
/// 为什么不是每次按当前右边缘算：状态项宽度每秒随网速文字变化（实测 96…112pt）。
/// 即使右边缘本身恒定，AppKit 每拍仍会按锚点重排已展开的 popover（实测面板 x 在
/// 757…777 之间来回），所以「跟着最新右边缘走」永远是追着跑。
///
/// 因此口径收成一条：**展开时把右边缘记下来，这一次展开期间不再变**。
/// 目标 x = 记住的右边缘 − 面板宽度；窗口被系统挪走（`didMoveNotification`）就按回这个 x。
/// 结果是：面板在整次展开期间位置恒定，收起再开才会用新的右边缘。
@MainActor
enum PanelWindowPin {

    /// 本次展开记下的目标右边缘（屏幕坐标）；nil = 没展开 / 已摘除
    private static var targetRightEdge: CGFloat?
    private static weak var panelWindow: NSWindow?
    private static var mover: NSObjectProtocol?
    /// 防重入：自己改位置会再发一次 didMove，不加闸会递归
    private static var isPinning = false

    /// 面板显示后调用一次：记下右边缘、挂上「被挪走就按回来」的观察者，并立即对齐一帧
    ///
    /// - Parameters:
    ///   - popover: 已 show 过、能拿到窗口的 popover
    ///   - anchorView: 状态项按钮（只在这一刻读它的屏幕右边缘）
    ///   - logger: 记录纠正结果（便于取证复跑；传 nil 不打日志）
    static func attach(to popover: NSPopover,
                       anchorView: NSView?,
                       logger: LoggingService? = nil) {
        detach()
        guard let window = popover.contentViewController?.view.window,
              let anchor = anchorView,
              let anchorWindow = anchor.window else { return }
        targetRightEdge = anchorWindow
            .convertToScreen(anchor.convert(anchor.bounds, to: nil)).maxX
        panelWindow = window
        mover = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
                // 观察者不捕获 note（跨隔离域传 Notification 会被判数据竞争）：目标只有一个窗口
                MainActor.assumeIsolated { pin(logger: logger) }
            }
        pin(logger: logger)
    }

    /// 收起后摘掉观察者与目标（下次展开重新取右边缘）
    static func detach() {
        if let mover { NotificationCenter.default.removeObserver(mover) }
        mover = nil
        panelWindow = nil
        targetRightEdge = nil
    }

    /// 纠正横向位置（宽度 / 高度一律不动：改宽度会触发 popover 再次居中）
    private static func pin(logger: LoggingService?) {
        guard !isPinning, let window = panelWindow, let rightEdge = targetRightEdge else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let targetX = PanelAnchor.pinnedX(panelWidth: window.frame.width,
                                          statusItemMaxX: rightEdge,
                                          visibleMinX: visible.minX,
                                          visibleMaxX: visible.maxX)
        guard abs(window.frame.origin.x - targetX) > 0.5 else { return }
        let before = window.frame.origin.x
        isPinning = true
        var frame = window.frame
        frame.origin.x = targetX
        window.setFrame(frame, display: false)
        isPinning = false
        logger?.debug("面板横向钉住：x \(before) → \(targetX)（记住的右边缘 \(rightEdge)）")
    }
}
