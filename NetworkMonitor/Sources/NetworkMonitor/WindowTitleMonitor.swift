@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// 窗口标题获取器：使用 Accessibility API 获取前台应用的活动窗口标题
/// 仅在应用切换时单次调用，几乎不消耗资源
enum WindowTitleMonitor {

    /// 获取指定应用的活动窗口标题
    /// - Parameter app: 正在运行的应用
    /// - Returns: 窗口标题，如果无法获取则返回 nil
    static func title(for app: NSRunningApplication) -> String? {
        guard app.isActive else { return nil }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // 获取焦点窗口
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else {
            // 尝试直接从应用获取窗口标题
            var title: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXTitleAttribute as CFString,
                &title
            )
            return titleResult == .success ? (title as? String) : nil
        }

        // 从焦点窗口获取标题
        let windowElement = window as! AXUIElement
        var windowTitle: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &windowTitle
        )

        return titleResult == .success ? (windowTitle as? String) : nil
    }
}
