#if DEBUG
import AppKit

// MARK: - 贴图窗手势探针：事件投递原语（仅 DEBUG）

/// 从 `PinDragProbe` 拆出的事件投递原语（原文件已顶到 15,360 字节门禁）。
///
/// 5 个原语只投递 `CGEvent` 与 `usleep` 等待、不碰主线程状态，故 `nonisolated` 是语义正确；
/// 探针刻意在后台队列投递，主线程要空出来处理窗口事件。
extension PinDragProbe {

    // MARK: - 事件投递

    /// 一条完整的按下 → 分步拖动 → 松开
    nonisolated static func postDrag(from start: CGPoint, delta: CGSize) {
        let startCG = cgPoint(start)
        moveMouse(to: startCG)
        sleepMilliseconds(120)
        post(type: .leftMouseDown, at: startCG, button: .left)
        sleepMilliseconds(150)
        let steps = 10
        for step in 1...steps {
            let ratio = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: startCG.x + delta.width * ratio,
                                y: startCG.y + delta.height * ratio)
            post(type: .leftMouseDragged, at: point, button: .left)
            sleepMilliseconds(40)
        }
        sleepMilliseconds(120)
        post(type: .leftMouseUp,
             at: CGPoint(x: startCG.x + delta.width, y: startCG.y + delta.height),
             button: .left)
    }

    nonisolated static func moveMouse(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    nonisolated static func post(type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    nonisolated static func sleepMilliseconds(_ value: UInt32) {
        usleep(value * 1000)
    }

    /// AppKit（左下原点）→ CG 全局（左上原点）
    nonisolated static func cgPoint(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }
}
#endif
