import AppKit
import NetworkMonitorCore

// MARK: - 采集模式

/// 剪贴板采集模式（对应设计规格第 6 节的两个分支）
enum ClipboardCaptureMode: String, Sendable {
    /// 分支 B：后台 500ms 轮询 + 变更即读（当前默认；探针结论出来后只改默认值）
    case polling
    /// 分支 A：不轮询，仅在打开面板 / 点击「采集当前剪贴板」时读取一次
    case onDemand

    /// 中文描述（设置窗展示）
    var label: String {
        switch self {
        case .polling: return "后台轮询"
        case .onDemand: return "按需采集"
        }
    }
}

// MARK: - 面板位置策略

/// 面板定位策略（设置项「面板位置」）
enum ClipboardPanelPosition: String, Sendable {
    /// 鼠标所在屏的底部（默认）
    case mouseScreen
    /// 主屏底部
    case primaryScreen
    /// 鼠标所在位置附近
    case mouseLocation

    var label: String {
        switch self {
        case .mouseScreen: return "鼠标所在屏底部"
        case .primaryScreen: return "主屏底部"
        case .mouseLocation: return "鼠标所在位置"
        }
    }
}

// MARK: - 偏好读写

/// 剪贴板偏好 — 收敛全部 KeyValueStorage 键名，避免键字符串散落各处
///
/// 线程模型：仅持有一个 Sendable 的 KeyValueStorage，读写均为轻量键值访问，可从任意线程调用。
final class ClipboardPreferences: Sendable {

    /// 开机自启键（与 MenuBarManager 共用，保持单一来源）
    static let launchAtStartupKey = "launchAtStartup"

    private enum Key {
        static let captureMode = "clipboard.captureMode"
        static let hotKeyCode = "clipboard.hotkey.keyCode"
        static let hotKeyModifiers = "clipboard.hotkey.modifiers"
        static let quickPaste = "clipboard.quickPasteEnabled"
        static let panelPosition = "clipboard.panelPosition"
        static let panelHeight = "clipboard.panelHeight"
        static let maxItems = "clipboard.maxItems"
        static let retentionDays = "clipboard.retentionDays"
        static let ignoredApps = "clipboard.ignoredBundleIDs"
        static let lastExternalApp = "clipboard.lastExternalBundleID"
        static let guidedAccess = "clipboard.hasGuidedAccess"
    }

    private let storage: any KeyValueStorage

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    // MARK: 采集

    /// 采集模式；默认分支 B（轮询）。探针结论出来后仅调整此处默认值。
    var captureMode: ClipboardCaptureMode {
        get { ClipboardCaptureMode(rawValue: storage.string(forKey: Key.captureMode) ?? "") ?? .polling }
        set { storage.set(newValue.rawValue, forKey: Key.captureMode) }
    }

    /// 是否已完成剪贴板访问权限一次性引导（分支 B 的引导标记）
    var hasGuidedClipboardAccess: Bool {
        get { storage.bool(forKey: Key.guidedAccess) }
        set { storage.set(newValue, forKey: Key.guidedAccess) }
    }

    // MARK: 热键

    /// 唤起面板的组合键（未设置时回退默认 ⌥⌘V）
    var panelToggleHotKey: HotKeyCombo {
        get {
            let code = storage.integer(forKey: Key.hotKeyCode)
            let modifiers = storage.integer(forKey: Key.hotKeyModifiers)
            guard code > 0, modifiers > 0 else { return .defaultPanelToggle }
            return HotKeyCombo(keyCode: UInt32(code), modifiers: UInt32(modifiers))
        }
        set {
            storage.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            storage.set(Int(newValue.modifiers), forKey: Key.hotKeyModifiers)
        }
    }

    /// ⌘1–⌘9 快速粘贴开关（默认开启）
    var quickPasteEnabled: Bool {
        get { storage.object(forKey: Key.quickPaste) == nil ? true : storage.bool(forKey: Key.quickPaste) }
        set { storage.set(newValue, forKey: Key.quickPaste) }
    }

    // MARK: 面板

    /// 面板定位策略
    var panelPosition: ClipboardPanelPosition {
        get { ClipboardPanelPosition(rawValue: storage.string(forKey: Key.panelPosition) ?? "") ?? .mouseScreen }
        set { storage.set(newValue.rawValue, forKey: Key.panelPosition) }
    }

    /// 面板高度（默认 260）
    var panelHeight: Double {
        get {
            let value = storage.double(forKey: Key.panelHeight)
            return value > 0 ? value : 260
        }
        set { storage.set(newValue, forKey: Key.panelHeight) }
    }

    // MARK: 存储上限

    /// 最大条数（默认 500）
    var maxItems: Int {
        get {
            let value = storage.integer(forKey: Key.maxItems)
            return value > 0 ? value : ClipboardLimit.defaultMaxItems
        }
        set { storage.set(newValue, forKey: Key.maxItems) }
    }

    /// 保留天数（默认 30，收藏豁免）
    var retentionDays: Int {
        get {
            let value = storage.integer(forKey: Key.retentionDays)
            return value > 0 ? value : ClipboardLimit.defaultRetentionDays
        }
        set { storage.set(newValue, forKey: Key.retentionDays) }
    }

    // MARK: 黑名单与目标 App

    /// 忽略（黑名单）应用 bundleID 集合
    var ignoredBundleIDs: Set<String> {
        get { Set((storage.object(forKey: Key.ignoredApps) as? [String]) ?? []) }
        set { storage.set(Array(newValue).sorted(), forKey: Key.ignoredApps) }
    }

    /// 最近一次「非本 App」的前台 bundleID 缓存（面板唤起时本 App 在前台则回退到它）
    var lastExternalBundleID: String? {
        get { storage.string(forKey: Key.lastExternalApp) }
        set { storage.set(newValue ?? "", forKey: Key.lastExternalApp) }
    }
}
