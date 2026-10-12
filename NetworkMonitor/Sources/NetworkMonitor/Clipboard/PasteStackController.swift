import AppKit
import ApplicationServices
import NetworkMonitorCore

// MARK: - Paste Stack 状态机

/// Paste Stack 控制器 — 入栈 / 出栈 / 推进 / 清空的唯一持有者，视图只读状态
///
/// 监听方式：NSEvent.addGlobalMonitorForEvents(matching: .keyDown)，禁止使用事件拦截（Event Tap）——
/// 事件拦截的回调一旦超时会被系统禁用，并阻塞全系统的键盘输入。
/// 全局 monitor 不改写事件、不阻塞；代价是无法拦截目标 App 原生 ⌘V，属规格第 14 节已知取舍。
@MainActor
final class PasteStackController {

    private let repository: any ClipboardRepository
    private let writer: any ClipboardWriter
    private let logger: LoggingService

    private var monitor: Any?
    /// 队首在前（下标 + 1 即 stack_position）
    private var positions: [UUID] = []
    /// 栈内条目缓存（出栈时取内容写剪贴板）
    private var itemsByID: [UUID: ClipboardItem] = [:]
    /// 上次清空以来累计入栈条数（面板显示「栈 2 / 5」的分子分母）
    private var insertedTotal = 0

    /// 辅助功能权限（无权限时全局 monitor 静默不回调，必须显式暴露状态，不得静默失败）
    private(set) var accessibilityGranted = false
    /// 状态变化回调（栈进度 / 权限状态变化）
    var onStateChange: (() -> Void)?

    init(repository: any ClipboardRepository,
         writer: any ClipboardWriter,
         logger: LoggingService = AppContext.shared.logger) {
        self.repository = repository
        self.writer = writer
        self.logger = logger
    }

    // MARK: 生命周期

    func start() {
        refreshAccessibility()
        reloadStack()
        installMonitor()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: 状态读取（视图只读）

    /// 队首到队尾的条目 id
    var orderedIDs: [UUID] { positions }
    /// 剩余条数
    var remainingCount: Int { positions.count }
    /// 累计入栈条数（分母）
    var stackTotal: Int { max(insertedTotal, positions.count) }
    /// 是否在栈内
    func contains(id: UUID) -> Bool { positions.contains(id) }

    /// 从数据库重新读取栈状态（面板打开时调用，保证视图与库一致）
    func reloadStack() {
        let stackItems = repository.fetchClipboardStack()
        positions = stackItems.map(\.id)
        itemsByID = Dictionary(stackItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        insertedTotal = max(insertedTotal, positions.count)
        onStateChange?()
    }

    // MARK: 入栈 / 出栈 / 清空

    /// 入栈：追加到队尾并重新编号
    /// - Returns: 是否成功（无辅助功能权限时拒绝入栈，由调用方给出文案）
    @discardableResult
    func push(id: UUID) -> Bool {
        guard accessibilityGranted else {
            logger.warning("Paste Stack 入栈被拒绝：缺少辅助功能权限")
            return false
        }
        guard !positions.contains(id) else { return true }
        positions.append(id)
        insertedTotal = max(insertedTotal + 1, positions.count)
        persist()
        return true
    }

    /// 清空整栈（对应 ⌘⇧S）
    func removeAll() {
        guard !positions.isEmpty else { return }
        positions.removeAll()
        itemsByID.removeAll()
        insertedTotal = 0
        persist()
    }

    /// 全局 ⌘V 推进：贴出队首并弹出队列，其余项整体前移
    ///
    /// 无法拦截改写目标 App 的原生 ⌘V（规格第 14 节已知取舍）：
    /// 这里把队首内容写入系统剪贴板，由同一按键触发的原生粘贴读取。
    func advanceOnPaste() {
        guard let id = positions.first else { return }
        let item = itemsByID[id] ?? repository.fetchClipboardItem(id: id)
        positions.removeFirst()
        itemsByID[id] = nil
        persist()
        guard let item else { return }
        if !writer.write(item, asPlainText: false) {
            logger.warning("Paste Stack 队首内容写回剪贴板失败（图片可能已丢失）")
        }
    }

    // MARK: 辅助功能权限

    /// 刷新权限状态（启动时与设置窗打开时调用）
    @discardableResult
    func refreshAccessibility() -> Bool {
        // 键名常量 kAXTrustedCheckOptionPrompt 在 Swift 6 下是可变全局量，改用其文档字面值
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted {
            logger.warning("未获得辅助功能权限：Paste Stack 的 ⌘V 监听不会生效")
        }
        onStateChange?()
        return accessibilityGranted
    }

    /// 请求权限并跳转系统设置（用户显式点击时调用）
    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    /// 跳转「系统设置 → 隐私与安全性 → 辅助功能」
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: 内部实现

    /// 安装全局 ⌘V 监听（无权限时不安装，避免假装在工作）
    private func installMonitor() {
        guard monitor == nil, accessibilityGranted else { return }
        let keyCodeV = Self.virtualKeyCodeV
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 全局 monitor 回调在非主线程交付：只取基本值类型，NSEvent 禁止跨线程传递
            let isRepeat = event.isARepeat
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // 长按 ⌘V 的 key repeat 过滤：只有非 repeat 的首次 keyDown 才推进粘贴栈
            guard !isRepeat, keyCode == keyCodeV, flags == .command else { return }
            Task { @MainActor in self?.advanceOnPaste() }
        }
    }

    /// 写入 stack_position 并广播变更（未列出的条目由仓储清空为 NULL）
    private func persist() {
        repository.updateClipboardStackPositions(positions)
        AppEvents.postClipboardChanged()
        onStateChange?()
    }

    /// ⌘V 虚拟键码（kVK_ANSI_V，避免在 @Sendable 闭包里访问隔离静态量）
    private static let virtualKeyCodeV: UInt16 = 9
}
