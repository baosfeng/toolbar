import AppKit
import NetworkMonitorCore

// MARK: - 截图失败提示

/// 截图失败时的用户可见提示 — 截图键按下去必须有结果，不能只在日志里留一行
///
/// 不用系统通知：本 App 走自签名身份，通知中心对未注册 bundle 的进程会抛
/// bundleProxyForCurrentProcess is nil 直接崩溃；也没人想要一条留在通知中心的失败记录。
/// 这里用屏幕上方居中的轻提示条，自动淡出，不拦鼠标与键盘。
@MainActor
enum SnipFailureNotice {

    /// 展示失败原因（日志与轻提示都在这里收口）
    static func present(message: String, logger: LoggingService) {
        logger.warning("截图失败提示：\(message)")
        SnipHintWindow.show("截图失败：" + message)
    }
}

/// 轻提示条：屏幕上方居中，自动淡出
@MainActor
final class SnipHintWindow: NSWindow {

    private static var current: SnipHintWindow?

    static func show(_ text: String) {
        current?.close()
        let width = min(max(CGFloat(text.count) * 9 + 44, 240), 560)
        let frame = NSRect(x: 0, y: 0, width: width, height: 44)
        let window = SnipHintWindow(contentRect: frame, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        // 必须关掉：NSWindow 默认 close 时释放自己，而静态变量仍持着引用，
        // 动画结束回调里再 close 就是 use-after-free（实测 SIGSEGV 崩在主循环 autoreleasePool)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let backdrop = NSView(frame: frame)
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        backdrop.layer?.cornerRadius = 10
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = frame.insetBy(dx: 14, dy: 12)
        backdrop.addSubview(label)
        window.contentView = backdrop

        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: screen.midX - width / 2, y: screen.maxY - 92))
        }
        window.alphaValue = 0
        window.orderFrontRegardless()
        current = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                window.animator().alphaValue = 0
            } completionHandler: {
                window.close()
                if SnipHintWindow.current === window { SnipHintWindow.current = nil }
            }
        }
    }
}
