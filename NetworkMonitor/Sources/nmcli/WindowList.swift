import CoreGraphics
import Foundation

// MARK: - 窗口枚举（必须走 CGWindowList）

/// 一个窗口的 CGWindowList 快照
///
/// 为什么不走 AX：菜单面板是 `NSPanel`（`.nonactivatingPanel`），既不在 `AXWindows` 里，
/// 也没有任何 AX 元素代表它——只有 CGWindowList 能拿到它的 id / layer / alpha / bounds。
/// 实测面板：`layer=25 alpha=1.0 onscreen=true`。
struct WindowInfo {
    let id: Int
    let pid: pid_t
    let layer: Int
    let alpha: Double
    let onscreen: Bool
    let bounds: CGRect
    let title: String
    let owner: String

    /// 面板图层：菜单面板 / 浮层都在这个 layer（25 = statusBar 级别）
    static let panelLayer = 25

    var describe: String {
        "\(id)\tlayer=\(layer)\talpha=\(String(format: "%.2f", alpha))"
            + "\tonscreen=\(onscreen)\t\(Format.rect(bounds))\t\(title)"
    }
}

enum WindowList {

    /// 全量窗口（`.optionAll`：含离屏与 alpha=0 的窗口，取证时要看「曾经存在过」）
    static func all() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
            let boundsDict = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bounds = CGRect(x: boundsDict["X"] as? Double ?? 0,
                                y: boundsDict["Y"] as? Double ?? 0,
                                width: boundsDict["Width"] as? Double ?? 0,
                                height: boundsDict["Height"] as? Double ?? 0)
            return WindowInfo(id: entry[kCGWindowNumber as String] as? Int ?? -1,
                              pid: pid_t(pid),
                              layer: entry[kCGWindowLayer as String] as? Int ?? -1,
                              alpha: entry[kCGWindowAlpha as String] as? Double ?? -1,
                              onscreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false,
                              bounds: bounds,
                              title: entry[kCGWindowName as String] as? String ?? "",
                              owner: entry[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    static func windows(of pid: pid_t) -> [WindowInfo] {
        all().filter { $0.pid == pid }
    }

    /// 真正在屏幕上的窗口（判据见 `isPresent`）
    ///
    /// 刚创建 / 正在收起的窗口会被系统标成 1x1 且 alpha=0，直接按 onscreen 取会拿到假窗口。
    static func visibleWindows(of pid: pid_t) -> [WindowInfo] {
        windows(of: pid).filter { $0.onscreen && $0.alpha > 0.5 && $0.bounds.width >= 2 }
    }

    /// 面板窗口（layer 25，可见）—— 菜单面板与各类浮层都在这个图层
    static func panel(of pid: pid_t, layer: Int = WindowInfo.panelLayer) -> WindowInfo? {
        visibleWindows(of: pid).first { $0.layer == layer }
    }

    /// 按图层找，忽略可见性（查「这个窗口还在不在」时用）
    static func matching(pid: pid_t, layer: Int) -> [WindowInfo] {
        windows(of: pid).filter { $0.layer == layer }
    }

    /// 窗口「此刻真的看得见」—— 唯一的可见性判据，`wait-window` 与 `assert window` 共用
    ///
    /// 只判 `onscreen` 会误判：面板收起后系统仍把它留在列表里，标成
    /// `onscreen=true alpha=0.00 1x1`（实测），看起来「还在」其实已经看不见了。
    /// 因此必须三个条件同时成立：onscreen、alpha > 0.5、宽高都 ≥ 2pt。
    static func isPresent(_ window: WindowInfo, layer: Int) -> Bool {
        window.layer == layer && window.onscreen && window.alpha > 0.5
            && window.bounds.width >= 2 && window.bounds.height >= 2
    }

    /// 某图层当前可见的窗口（`isPresent` 口径）
    static func presentWindows(of pid: pid_t, layer: Int) -> [WindowInfo] {
        windows(of: pid).filter { isPresent($0, layer: layer) }
    }
}
