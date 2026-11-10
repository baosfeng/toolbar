import AppKit
import NetworkMonitorCore

// MARK: - 首帧重绘（拿不到绘图上下文时）

extension SnipOverlayView {

    /// 没有绘图上下文时，把重绘排到下一轮主循环
    /// 
    /// 场景：窗口刚 orderFrontRegardless 时 WindowServer 侧的 back store 还没建好，
    /// 这一轮 draw 拿不到 NSGraphicsContext。早期实现直接 return，needsDisplay 已被清掉，
    /// 覆盖层就一直空白（实测「按截图键毫无反应」的第二个成因）。
    /// 重试上限 6 次，超限后记日志放弃，避免无限重绘把主线程打满。
    func scheduleRedrawAfterMissingContext() {
        guard redrawAttempts < 6 else {
            AppContext.shared.logger.warning("截图覆盖层首帧绘制多次失败，放弃重试")
            return
        }
        redrawAttempts += 1
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
        }
    }
}
