import Foundation

// MARK: - CLI 页面输出通道

/// `nmcli page` 的目标页面标识
///
/// app 侧（收到命令后打开页面）与 nmcli 侧（发命令）认同一套字符串；解析放在不依赖 AppKit
/// 的展示逻辑层，TestRunner 可以直接断言，不必起真机。
///
/// 为什么不用环境变量：旧的一批 `NM_*` 探针要在启动时另起一个进程、渲染完 `exit(0)`，
/// 既影响用户当前使用，也只能在 app 未运行时跑。这里的通道是**对运行中的 app 发命令**，
/// 打开页面后原地输出，不重启、不退出、不改用户偏好。
public enum CLIPageTarget: Equatable, Sendable {
    /// 统一设置窗口；sectionID 为 nil 表示当前 / 默认分类
    case settings(sectionID: String?)
    /// 屏幕底部的剪贴板历史浮层
    case clipboard
    /// 菜单面板；tabID 为 nil 表示保持当前分页
    case menu(tabID: String?)
    /// 不切换任何页面，只输出当前已可见的页面
    case current
}

extension CLIPageTarget {

    /// 命令里的字符串形式（与 `parse` 互补）
    public var rawValue: String {
        switch self {
        case .current: return "current"
        case .clipboard: return "clipboard"
        case .menu(let tabID): return tabID.map { "menu.\($0)" } ?? "menu"
        case .settings(let sectionID): return sectionID.map { "settings.\($0)" } ?? "settings"
        }
    }

    /// 解析命令字符串
    ///
    /// 空串按 `current` 处理（只输出当前页面）；不认识的写法返回 nil，由调用方报错，
    /// 不做「猜一个最像的页面」——猜错会输出一张看起来正常、其实不是目标页的图。
    public static func parse(_ raw: String) -> CLIPageTarget? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .current }
        switch text {
        case "current":
            return .current
        case "clipboard", "clipboard-panel":
            return .clipboard
        case "menu":
            return .menu(tabID: nil)
        case "settings":
            return .settings(sectionID: nil)
        default:
            break
        }
        if text.hasPrefix("menu.") {
            let id = String(text.dropFirst("menu.".count))
            return id.isEmpty ? .menu(tabID: nil) : .menu(tabID: id)
        }
        if text.hasPrefix("settings.") {
            let id = String(text.dropFirst("settings.".count))
            return id.isEmpty ? .settings(sectionID: nil) : .settings(sectionID: id)
        }
        return nil
    }

    /// 该目标对应的页面是否需要「先打开再截图」
    public var needsOpening: Bool {
        switch self {
        case .current: return false
        case .settings, .clipboard, .menu: return true
        }
    }
}

/// CLI 页面通道的跨进程约定 —— app 与 nmcli 各持同一份常量，改名只改这里
public enum CLIPageChannel {
    /// 命令通知名（app 侧监听、nmcli 侧投递）
    public static let commandName = "com.bsfeng.yilan.cli.page"
    /// userInfo：目标页面字符串（`CLIPageTarget.rawValue`）
    public static let keyTarget = "target"
    /// 回执通知名（app 打开页面后投递，nmcli 侧据此得知窗口已就位）
    public static let receiptName = "com.bsfeng.yilan.cli.page.done"
    /// userInfo：调用方生成的请求标识（回执里原样带回，便于并发调用对账）
    public static let keyRequest = "request"
    /// userInfo：目标窗口的 windowNumber（回执专用；CGWindowList / screencapture -l 都认它）
    public static let keyWindowNumber = "window"

    /// 菜单面板分页的稳定 id —— 与 App 层 `MenuPanelTab.stableID` 同源
    ///
    /// nmcli 是独立可执行 target，看不到 App 层的枚举，只能共持一份字符串表；
    /// 两边不一致时 `nmcli page open menu.<id>` 会退化成「保持当前分页」，不会崩。
    public static let knownMenuTabIDs = ["network", "transfer", "credits", "token", "system"]

    /// 设置窗口分类 —— 与 App 层 `SettingsSection.rawValue` 同源
    public static let knownSettingsSectionIDs = [
        "general", "appearance", "providers", "clipboard", "capture",
        "transfer", "notifications", "token", "permissions", "system", "about"
    ]
}
