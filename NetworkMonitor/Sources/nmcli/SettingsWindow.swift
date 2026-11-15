import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 设置窗口（打开 / 切页 / 关闭）

/// 统一设置窗口的自动化入口
///
/// 设置窗口是标准 `AXStandardWindow`（在 `AXWindows` 里、标题「设置」），
/// 所以窗口本身的开关与读取全部走 AX；但侧栏九分类是**自绘行**，
/// AX 里只有 `AXStaticText` 没有按钮，只能按它上报的 bounds 中心做坐标点击。
enum SettingsWindow {

    /// 设置窗口（AX 口径）
    static func window(of target: AppTarget) -> AXNode? {
        guard let raw = AXReader.attribute(target.axRoot, kAXWindowsAttribute as String),
              let windows = raw as? [AXUIElement] else { return nil }
        for window in windows {
            let node = AXReader.node(window)
            if node.title == "设置" || node.title.contains("设置") { return node }
        }
        return nil
    }

    /// 打开设置：走「一览」菜单里的「设置…」项（与真实用户路径同一条）
    ///
    /// 为什么不用 ⌘,：菜单项上确实标着 `cmd=,`，但键盘事件在便携二进制的进程里
    /// 未必拿到投递权限；AXPress 菜单项则是确定的。打开前先把菜单展开。
    @discardableResult
    static func open(_ target: AppTarget, timeoutMilliseconds: Int = 3000) -> Bool {
        if window(of: target) != nil { return true }
        guard let barItem = appMenuBarItem(of: target) else { return false }
        _ = Actions.press(barItem)
        usleep(400_000)
        guard let item = MenuBarReader.appMenuItems(of: target).first(where: { $0.title.contains("设置") }) else {
            return false
        }
        _ = Actions.press(item)
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
        repeat {
            if window(of: target) != nil { return true }
            usleep(60_000)
        } while Date() < deadline
        return false
    }

    /// 关闭设置窗口：AXPress 关闭按钮（红绿灯按钮在 AX 里有独立元素）
    @discardableResult
    static func close(_ target: AppTarget, timeoutMilliseconds: Int = 3000) -> Bool {
        guard let window = window(of: target) else { return true }
        if let raw = AXReader.attribute(window.element, kAXCloseButtonAttribute as String),
           CFGetTypeID(raw) == AXUIElementGetTypeID() {
            let button = AXReader.node(raw as! AXUIElement)
            if Actions.press(button) {
                return waitClosed(target, timeoutMilliseconds: timeoutMilliseconds)
            }
        }
        _ = window
        return waitClosed(target, timeoutMilliseconds: timeoutMilliseconds)
    }

    private static func waitClosed(_ target: AppTarget, timeoutMilliseconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
        repeat {
            if window(of: target) == nil { return true }
            usleep(60_000)
        } while Date() < deadline
        return false
    }

    /// 切到某个分类页：侧栏行是自绘的，按 `AXStaticText` 的实测位置点中心
    ///
    /// 取第一个「值 == 分类名 且 x 在侧栏范围内」的文本，避免命中内容区里同名的标题。
    @discardableResult
    static func selectSection(_ target: AppTarget, name: String, settleMilliseconds: Int = 500) -> Bool {
        guard let window = window(of: target) else { return false }
        let sidebarMaxX = window.position.map { $0.x + 220 } ?? .greatestFiniteMagnitude
        let candidates = AXReader.collect(from: window.element, maxDepth: 6) { node in
            guard node.role == "AXStaticText", node.value == name, let position = node.position else { return false }
            return position.x < sidebarMaxX
        }
        guard let row = candidates.first, let center = row.center else { return false }
        Actions.click(at: center)
        usleep(UInt32(settleMilliseconds) * 1000)
        return true
    }

    /// 「一览」菜单栏菜单项（用于展开菜单）
    private static func appMenuBarItem(of target: AppTarget) -> AXNode? {
        guard let raw = AXReader.attribute(target.axRoot, kAXMenuBarAttribute as String),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        for child in AXReader.children(raw as! AXUIElement) {
            let node = AXReader.node(child)
            if node.title == target.name { return node }
        }
        return nil
    }
}
