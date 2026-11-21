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
public final class PasteStackController {

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
    public private(set) var accessibilityGranted = false
    /// 状态变化回调（栈进度 / 权限状态变化）
    public var onStateChange: (() -> Void)?
    /// 请求辅助功能权限（组合根接到权限中心；本控制器不再自己拼系统设置深链）
    public var onRequestAccessibility: (() -> Void)?
    /// 栈推进回调（仅「⌘V 贴出队首」时触发；入栈 / 重载 / 清空不触发）
    ///
    /// 与 onStateChange 分开的原因：后者被入栈、重载、清空共用，
    /// 触觉反馈只该在真正推进（队首被贴出）时打一次，否则每次打开面板都会被震一下。
    public var onAdvance: (() -> Void)?

    /// 日志一律由调用方显式注入（功能层不取 AppContext.shared）
    public init(repository: any ClipboardRepository,
                writer: any ClipboardWriter,
                logger: LoggingService) {
        self.repository = repository
        self.writer = writer
        self.logger = logger
    }

    // MARK: 生命周期

    public func start() {
        syncAccessibility(Self.probeAccessibility())
        reloadStack()
    }

    /// 停止全局监听（组合根退出 / 边界测试收尾都要能主动收口）
    public func stop() {
        removeMonitor()
    }

    // MARK: 状态读取（视图只读）

    // 放宽为 public：面板读 remainingCount / stackTotal，跨 target 边界测试断言 orderedIDs /
    // contains(id:) —— 「顺序即粘贴顺序」正是把这层抽成独立 target 的理由之一。

    /// 队首到队尾的条目 id
    public var orderedIDs: [UUID] { positions }
    /// 剩余条数
    public var remainingCount: Int { positions.count }
    /// 累计入栈条数（分母）
    public var stackTotal: Int { max(insertedTotal, positions.count) }
    /// 是否在栈内
    public func contains(id: UUID) -> Bool { positions.contains(id) }

    /// 从数据库重新读取栈状态（面板打开时调用，保证视图与库一致）
    public func reloadStack() {
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
    public func push(id: UUID) -> Bool {
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
    public func removeAll() {
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
    public func advanceOnPaste() {
        guard let id = positions.first else { return }
        let item = itemsByID[id] ?? repository.fetchClipboardItem(id: id)
        positions.removeFirst()
        itemsByID[id] = nil
        persist()
        onAdvance?()
        guard let item else { return }
        if !writer.write(item, asPlainText: false) {
            logger.warning("Paste Stack 队首内容写回剪贴板失败（图片可能已丢失）")
        }
    }

    // MARK: 辅助功能权限

    /// 静默读取辅助功能授权态（不弹系统框）
    ///
    /// 唯一读取入口：`SystemPermissionCenter` 与设置页都走这里，不各写一份 API 调用与选项字典。
    /// 命名常量 kAXTrustedCheckOptionPrompt 在 Swift 6 下是可变全局量，改用其文档字面值。
    nonisolated public static func probeAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    /// 把最新授权态下发进来（授权后补装全局监听，撤销后拆除）
    ///
    /// 为什么需要外部驱动：用户去系统设置勾上后回到应用，全局 monitor 不会自己长出来——
    /// 旧实现只在 `start()` 读一次，授权后必须重启应用才能用 Paste Stack。
    @discardableResult
    public func syncAccessibility(_ granted: Bool) -> Bool {
        let changed = granted != accessibilityGranted
        accessibilityGranted = granted
        if granted {
            installMonitor()
        } else {
            removeMonitor()
        }
        if changed {
            if granted {
                logger.info("辅助功能权限已生效：Paste Stack 的 ⌘V 监听已就绪")
            } else {
                logger.warning("未获得辅助功能权限：Paste Stack 的 ⌘V 监听不会生效")
            }
            onStateChange?()
        }
        return granted
    }

    /// 请求权限并跳转系统设置（用户显式点击时调用）
    ///
    /// 具体动作（登记 + 深链）不在本控制器：面板只持有 `onRequestAccessibility`，
    /// 由组合根接到 `SystemPermissionCenter.request(.accessibility)` —— 深链只在那里拼一次。
    public func requestAccessibilityPermission() {
        onRequestAccessibility?()
    }

    // MARK: 内部实现

    /// 拆除全局 ⌘V 监听（授权被撤销 / 应用退出时）
    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

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
