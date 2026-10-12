import AppKit
import ApplicationServices
import CoreGraphics
import NetworkMonitorCore

// MARK: - 粘贴结果

/// 粘贴结果 — 面板据此给出提示（降级路径必须让用户知道发生了什么）
enum ClipboardPasteOutcome: Equatable {
    /// 已写入剪贴板并合成 ⌘V
    case pasted
    /// 仅写入剪贴板，需要用户手动粘贴（附中文原因）
    case copiedOnly(String)
    /// 写入失败（附中文原因）
    case failed(String)

    /// 面向用户的提示文案
    var message: String {
        switch self {
        case .pasted: return ""
        case .copiedOnly(let reason): return reason
        case .failed(let reason): return reason
        }
    }
}

// MARK: - 系统剪贴板写回实现

/// ClipboardWriter 的 App 层实现 — 所有写入都会在内部写入窗口内打上自激标记
///
/// 自激标记类型名取自 ClipboardPasteboardType.internalMarker，
/// 采集侧 PasteboardWatcher 依赖同一常量做忽略判定（大小写敏感，禁止改写）。
@MainActor
final class PasteboardWriter: ClipboardWriter {

    private let logger: LoggingService
    /// 内部写入窗口嵌套计数（begin/end 必须配对，嵌套时取最深一层）
    private var internalWriteDepth = 0

    private var markerType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(ClipboardPasteboardType.internalMarker)
    }

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    // MARK: ClipboardWriter

    @discardableResult
    func write(_ item: ClipboardItem, asPlainText: Bool) -> Bool {
        if asPlainText { return writeText(item.text ?? item.preview) }
        switch item.kind {
        case .image:
            guard let data = Self.pngData(at: item.imagePath) else {
                logger.warning("图片条目写回失败：原图缺失或无法解码")
                return false
            }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: .png)
            return write([pasteboardItem])
        case .file:
            return writeFileURLs(from: item.text ?? "")
        case .text, .rtf:
            return writeText(item.text ?? item.preview)
        }
    }

    @discardableResult
    func writeText(_ text: String) -> Bool {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(text, forType: .string)
        return write([pasteboardItem])
    }

    func beginInternalWrite() {
        internalWriteDepth += 1
    }

    /// 结束内部写入窗口
    ///
    /// 不主动清除已写入的自激标记：用户下一次复制会由系统整体替换剪贴板内容，标记自然消失；
    /// 主动改写现存剪贴板反而可能破坏用户数据。
    func endInternalWrite() {
        internalWriteDepth = max(0, internalWriteDepth - 1)
    }

    // MARK: 内部实现

    /// 统一写入口：清空后写入，并给首个载体打自激标记
    ///
    /// 标记是无条件的（协议契约：本实现任何写入都不得被自身采集器再次记录）；
    /// internalWriteDepth 只用于标记自激窗口是否处于展开态（合成 ⌘V 期间不结束该窗口）。
    private func write(_ pasteboardItems: [NSPasteboardItem]) -> Bool {
        guard let first = pasteboardItems.first else { return false }
        first.setData(Data(), forType: markerType)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(pasteboardItems) else {
            logger.error("写入系统剪贴板失败")
            return false
        }
        return true
    }

    /// 文件条目写回：每个路径一个 fileURL 载体
    private func writeFileURLs(from text: String) -> Bool {
        let paths = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return writeText(text) }
        let pasteboardItems = paths.map { path -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
            return pasteboardItem
        }
        return write(pasteboardItems)
    }

    /// 读取落盘原图并转 PNG 字节
    private static func pngData(at path: String?) -> Data? {
        guard let path, !path.isEmpty, let image = NSImage(contentsOfFile: path) else { return nil }
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}

// MARK: - 粘贴器

/// 粘贴器 — 目标 App 记忆与合成 ⌘V
///
/// 核心矛盾：面板要能打字就必须是 key window，此状态下合成的 ⌘V 会落回面板自身。
/// 解法：唤起面板时（面板尚未成为 key window）同步记录 frontmost 为目标 App，回车时不再取 frontmost。
@MainActor
final class ClipboardPaster {

    /// 写入剪贴板 → 合成 ⌘V 之间的固定延迟（设计规格第 7 节：80ms）
    private static let synthesizeDelay: TimeInterval = 0.08
    /// ⌘V 的虚拟键码（kVK_ANSI_V）
    private static let keyCodeV: CGKeyCode = 9

    private let writer: any ClipboardWriter
    private let preferences: ClipboardPreferences
    private let logger: LoggingService

    /// 本次唤起记录的目标 App bundleID（未识别到时为 nil，降级为仅复制）
    private(set) var targetBundleID: String?

    init(writer: any ClipboardWriter,
         preferences: ClipboardPreferences,
         logger: LoggingService = AppContext.shared.logger) {
        self.writer = writer
        self.preferences = preferences
        self.logger = logger
    }

    /// 是否已识别到可粘贴的目标 App
    var hasTargetApplication: Bool { targetBundleID != nil }

    // MARK: 目标 App 记忆

    /// 记录目标 App（唤起面板时调用）
    ///
    /// 【时序敏感·禁止改动调用位置】必须在面板 makeKeyAndOrderFront / makeKey 之前「同步」调用：
    /// 此刻面板尚未成为 key window，frontmost 仍是用户的真实目标 App；
    /// 若把本调用挪进动画完成回调、DispatchQueue.main.async 或 NSAnimationContext 的 completionHandler，
    /// 取到的 frontmost 只会是本 App，粘贴将永远落回自己 —— 禁止后移到任何异步路径。
    @discardableResult
    func recordTargetApplication() -> String? {
        let ownBundleID = Bundle.main.bundleIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != ownBundleID {
            targetBundleID = frontmost.bundleIdentifier
            if let bundleID = frontmost.bundleIdentifier {
                preferences.lastExternalBundleID = bundleID
            }
            return targetBundleID
        }
        // 唤起时 frontmost 就是本 App（例如从菜单栏图标打开面板）：回退到最近一次非本 App 的前台缓存
        if let cached = preferences.lastExternalBundleID, Self.isApplicationAlive(bundleID: cached) {
            targetBundleID = cached
        } else {
            targetBundleID = nil
            logger.warning("无可用的目标应用（缓存为空或已退出），本次降级为仅复制")
        }
        return targetBundleID
    }

    // MARK: 粘贴

    /// 粘贴选中条目
    ///
    /// 调用前必须已收起面板让出 key（由 ClipboardPanelController 先 orderOut 再调用）。
    /// 时序：写剪贴板（先打自激标记）→ 延迟 80ms → 合成 ⌘V；自激标记不主动清除，
    /// 由用户下一次复制整体替换剪贴板内容时自然消失（理由见 PasteboardWriter.endInternalWrite）。
    func paste(_ item: ClipboardItem,
               asPlainText: Bool,
               completion: (@MainActor (ClipboardPasteOutcome) -> Void)? = nil) {
        guard let bundleID = targetBundleID else {
            let outcome: ClipboardPasteOutcome = writer.write(item, asPlainText: asPlainText)
                ? .copiedOnly("未识别到目标应用，内容已复制，请手动粘贴")
                : .failed("写入剪贴板失败")
            completion?(outcome)
            return
        }
        // 没有辅助功能权限时系统会静默丢弃投递的按键事件：不得谎报「已粘贴」，降级为仅复制 + 引导授权
        let canSynthesize = AXIsProcessTrusted()
        // 自激标记窗口必须覆盖「写剪贴板 → 延迟 80ms → 合成 ⌘V」整段，否则 500ms 轮询会把刚粘贴的内容再记一条
        writer.beginInternalWrite()
        guard writer.write(item, asPlainText: asPlainText) else {
            writer.endInternalWrite()
            completion?(.failed("写入剪贴板失败：图片可能已丢失"))
            return
        }
        guard canSynthesize else {
            writer.endInternalWrite()
            completion?(.copiedOnly("需要辅助功能权限才能自动粘贴，内容已复制"))
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.synthesizeDelay * 1_000_000_000))
            guard let self else { return }
            let posted = self.synthesizePaste(to: bundleID)
            self.writer.endInternalWrite()
            completion?(posted ? .pasted : .copiedOnly("目标应用已退出，内容已复制，请手动粘贴"))
        }
    }

    /// 仅复制，不粘贴（对应 ⌘↵）
    @discardableResult
    func copyOnly(_ item: ClipboardItem, asPlainText: Bool = false) -> ClipboardPasteOutcome {
        writer.write(item, asPlainText: asPlainText) ? .copiedOnly("已复制到剪贴板") : .failed("写入剪贴板失败")
    }

    /// 把条目内容写入系统剪贴板（Paste Stack 推进用，不打合成按键）
    @discardableResult
    func writeToPasteboard(_ item: ClipboardItem, asPlainText: Bool = false) -> Bool {
        writer.write(item, asPlainText: asPlainText)
    }

    // MARK: 内部实现

    /// 合成 ⌘V：CGEvent 投递到当前前台 App（不做任何拦截改写，见规格第 14 节已知取舍）
    ///
    /// 无辅助功能权限时系统会静默丢弃事件，此处兜底再校验一次，杜绝「提示已粘贴但其实没粘上」。
    private func synthesizePaste(to bundleID: String) -> Bool {
        guard AXIsProcessTrusted() else {
            logger.warning("未获得辅助功能权限，跳过合成粘贴（事件会被系统丢弃）")
            return false
        }
        // 回退缓存的存活校验：目标 App 已退出时只写剪贴板，不合成按键
        guard Self.isApplicationAlive(bundleID: bundleID) else {
            logger.warning("目标应用已退出，跳过合成粘贴")
            return false
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCodeV, keyDown: false) else {
            logger.error("合成 ⌘V 失败：CGEvent 创建失败")
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    /// 目标 App 存活校验（非 nil 且未被终止）
    private static func isApplicationAlive(bundleID: String) -> Bool {
        guard !bundleID.isEmpty,
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        return !application.isTerminated
    }
}
