import AppKit
import NetworkMonitorCore
import NetworkMonitorUI
import NetworkMonitorFeatureClipboard

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
        static let paused = "clipboard.paused"
        static let pausedUntil = "clipboard.pausedUntil"
        static let hotKeyCode = "clipboard.hotkey.keyCode"
        static let hotKeyModifiers = "clipboard.hotkey.modifiers"
        static let quickPaste = "clipboard.quickPasteEnabled"
        static let panelPosition = "clipboard.panelPosition"
        static let panelHeight = "clipboard.panelHeight"
        static let panelHeightLayout = "clipboard.panelHeightLayout"
        static let maxItems = "clipboard.maxItems"
        static let maxBytes = "clipboard.maxBytes"
        static let retentionDays = "clipboard.retentionDays"
        static let ignoredApps = "clipboard.ignoredBundleIDs"
        static let lastExternalApp = "clipboard.lastExternalBundleID"
        static let guidedAccess = "clipboard.hasGuidedAccess"
        static let soundEffects = "clipboard.soundEffectsEnabled"
        static let haptics = "clipboard.hapticsEnabled"
        static let imageOCR = "clipboard.imageOCREnabled"
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

    /// 暂停开关的原始记录（默认 false）；「现在到底采不采」读 `isPausedNow`
    ///
    /// 与 `captureMode`（怎么采）是两个维度：这里决定「采不采」。开关与定时截止时刻分开存，
    /// 定时到点只让 `isPausedNow` 变假，不改写开关，故「到手动恢复」的暂停不会被动过。
    var isPaused: Bool {
        get { ClipboardPauseLogic.isPaused(storedValue: storage.object(forKey: Key.paused) as? Bool) }
        set { storage.set(newValue, forKey: Key.paused) }
    }

    /// 定时暂停的截止时刻（时间戳 0 = 无定时，暂停到手动恢复）
    var pausedUntil: Date {
        get { Date(timeIntervalSince1970: storage.double(forKey: Key.pausedUntil)) }
        set {
            let timestamp = newValue.timeIntervalSince1970
            storage.set(timestamp > 0 ? timestamp : 0, forKey: Key.pausedUntil)
        }
    }

    /// 当前是否真的暂停 —— 定时暂停到点返回 false，调用方据此自动恢复
    var isPausedNow: Bool {
        ClipboardPauseLogic.isPausedNow(paused: isPaused, pausedUntil: pausedUntil, now: Date())
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

    /// 面板高度可选范围 —— 下限是「卡片区刚好容下整卡」，上限与设置页滑块一致
    ///
    /// 与分段几何同源（ClipboardPanelLayout）：改卡片尺寸时这里自动跟着变，
    /// 设置页滑块与偏好读取共用同一份边界，不会再出现「滑块能拖到裁卡的高度」。
    static let heightRange: ClosedRange<Double> =
        ClipboardPanelLayout.minPanelHeight...ClipboardPanelLayout.maxPanelHeight

    /// 分段几何版本：2 = 面板只剩「工具条 + 卡片区」（详情区退成编辑浮层、提示行改为状态胶囊）
    static let panelHeightLayoutVersion = 2
    /// v1 分段里被删掉的固定高度：详情区 102 + 提示行 24
    ///
    /// 这里刻意写字面量而不是引用现常量 —— 它是**历史分段**的冻结值，跟现在的几何没关系；
    /// 引用现常量会让「以后调详情区高度」连带改写老用户的迁移结果。
    private static let legacyChromeHeight: Double = 126

    /// 面板高度（默认由分段几何给出：工具条 + 整卡）
    ///
    /// 读出来的值一律夹紧到 ClipboardPanelLayout 的上下限：下限保证卡片不被裁、
    /// 上限与设置页滑块一致。老用户存下的旧高度含已删除的两段，按同一张卡片来扣减
    /// （迁移在读取时完成、不回写偏好：同一个存量值每次读都得到同一个结果）。
    var panelHeight: Double {
        get {
            let stored = storage.double(forKey: Key.panelHeight)
            guard stored > 0 else { return ClipboardPanelLayout.defaultPanelHeight }
            return ClipboardPanelLayout.clampedHeight(
                Self.migratedHeight(stored,
                                   storedVersion: storage.integer(forKey: Key.panelHeightLayout)))
        }
        set {
            storage.set(newValue, forKey: Key.panelHeight)
            storage.set(Self.panelHeightLayoutVersion, forKey: Key.panelHeightLayout)
        }
    }

    /// 旧分段高度 → 新分段高度：扣掉已删除的详情区与提示行，卡片尺寸保持不变
    static func migratedHeight(_ stored: Double, storedVersion: Int) -> Double {
        guard stored > 0, storedVersion < panelHeightLayoutVersion else { return stored }
        return stored - legacyChromeHeight
    }

    // MARK: 图片文字识别

    /// 识别图片中文字开关（默认开启；关掉后新采集的图片条目不再识别，已有结果保留）
    var imageOCRRecognizeEnabled: Bool {
        get { storage.object(forKey: Key.imageOCR) == nil ? true : storage.bool(forKey: Key.imageOCR) }
        set { storage.set(newValue, forKey: Key.imageOCR) }
    }

    // MARK: 操作反馈

    /// 操作音效开关（默认关闭；开启后复制 / 粘贴 / 收藏 / 删除 / 失败会响）
    var soundEffectsEnabled: Bool {
        get { storage.object(forKey: Key.soundEffects) == nil ? false : storage.bool(forKey: Key.soundEffects) }
        set { storage.set(newValue, forKey: Key.soundEffects) }
    }

    /// 触觉反馈开关（默认开启；无触控板时系统自行忽略）
    var hapticsEnabled: Bool {
        get { storage.object(forKey: Key.haptics) == nil ? true : storage.bool(forKey: Key.haptics) }
        set { storage.set(newValue, forKey: Key.haptics) }
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

    /// 最大容量（字节，默认 100 MB；0 = 不限，收藏项与板内条目豁免清理但计入总量）
    ///
    /// 只在这里做「缺键 / 负值 → 默认值」的归一化；「0 = 不限」是合法值，必须原样透出，
    /// 否则用户设成不限会被悄悄改回 100 MB。
    var maxBytes: UInt64 {
        get {
            let stored = storage.object(forKey: Key.maxBytes) == nil ? nil : storage.integer(forKey: Key.maxBytes)
            return ClipboardLimit.normalizedMaxBytes(stored: stored)
        }
        set { storage.set(Int(clamping: newValue), forKey: Key.maxBytes) }
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
