import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 面板控制器

/// 剪贴板面板控制器 — 面板生命周期、定位、动画、按键拦截与动作执行
@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate, ClipboardPanelViewDelegate {

    private let panel: ClipboardPanel
    private let content: ClipboardPanelView
    private let repository: any ClipboardRepository
    private let captureService: any ClipboardCaptureService
    private let paster: ClipboardPaster
    private let stack: PasteStackController
    private let preferences: ClipboardPreferences
    private let logger: LoggingService
    /// ⌘, 打开剪贴板设置（组合根注入，复用既有设置窗打开路径）
    private let onRequestSettings: (() -> Void)?

    private var items: [ClipboardItem] = []
    private var filteredItems: [ClipboardItem] = []
    private var selectedIndex = -1
    /// 面板已收起时的降级提示
    private var pendingHint: String?
    /// 面板收起期间有剪贴板变更，下次打开时重读
    private var pendingReload = false
    nonisolated(unsafe) private var localKeyMonitor: Any?
    nonisolated(unsafe) private var clipboardObserver: NSObjectProtocol?

    init(repository: any ClipboardRepository, captureService: any ClipboardCaptureService,
         paster: ClipboardPaster, stack: PasteStackController, onRequestSettings: (() -> Void)? = nil,
         preferences: ClipboardPreferences, logger: LoggingService = AppContext.shared.logger) {
        self.repository = repository; self.captureService = captureService
        self.paster = paster; self.stack = stack; self.onRequestSettings = onRequestSettings
        self.preferences = preferences; self.logger = logger
        let rect = NSRect(x: 0, y: 0, width: 640, height: 260)
        self.panel = ClipboardPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        self.content = ClipboardPanelView(frame: rect)
        super.init()
        configurePanel()
        observeClipboardChanges()
        stack.onStateChange = { [weak self] in self?.syncStackState() }
    }

    nonisolated deinit {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let clipboardObserver { NotificationCenter.default.removeObserver(clipboardObserver) }
    }

    /// 唤起 / 收起
    func toggle() {
        if panel.isVisible { hide(animated: true) } else { show() }
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
        panel.onPerformKeyEquivalent = { [weak self] event in self?.handleKeyDown(event) ?? false }
        content.delegate = self; content.autoresizingMask = [.width, .height]

        // 面板底：NSVisualEffectView(.hudWindow)，圆角 14pt
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14; background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        content.frame = background.bounds
        background.addSubview(content)
        panel.contentView = background

        // 本地事件监听：先于 responder chain 拿到按键（搜索框聚焦时字段编辑器会吃掉 ⌫ / ⌘D / Tab）
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func observeClipboardChanges() {
        clipboardObserver = NotificationCenter.default.addObserver(forName: AppEvents.clipboardChanged,
                                                                  object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadItems() }
        }
    }

    func show() {
        // 【时序敏感·禁止调整顺序】必须先「同步」记录目标 App，再 makeKeyAndOrderFront：
        // 此刻面板尚未成为 key window，frontmost 仍是用户真实的目标 App；
        // 若把这一行挪到 makeKeyAndOrderFront 之后，或放进动画完成回调 / DispatchQueue.main.async，
        // 取到的 frontmost 只会是本 App，合成的 ⌘V 永远落回面板 —— 禁止后移到任何异步路径。
        paster.recordTargetApplication()

        // 收起期间有变更才重读数据库；渲染只在面板打开这里发生（收起时不渲染）
        if pendingReload || items.isEmpty { items = repository.fetchAllClipboardItems(kind: nil) }
        pendingReload = false
        applyFilter()
        stack.reloadStack()
        // 分支 A / B 通用：打开瞬间读一次（changeCount 未变则静默返回，不重复读）
        captureService.captureNow()
        if let hint = pendingHint { content.showHint(hint); pendingHint = nil }
        positionPanel()
        let finalFrame = panel.frame
        panel.alphaValue = 0
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: -14), display: false)
        panel.makeKeyAndOrderFront(nil)
        content.focusSearchField()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }, completionHandler: nil)
    }

    /// 收起面板；animated=false 用于粘贴路径 —— 立即 orderOut 让出 key，合成的 ⌘V 才落得到目标 App
    func hide(animated: Bool) {
        guard panel.isVisible else { return }
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.panel.orderOut(nil) }
        })
    }

    func windowDidResignKey(_ notification: Notification) { hide(animated: true) }

    /// 定位：几何计算见 ClipboardPanelGeometry（目标屏 visibleFrame 底部）
    private func positionPanel() {
        let mouse = NSEvent.mouseLocation, position = preferences.panelPosition
        let visible = ClipboardPanelGeometry.targetScreen(position: position, mouse: mouse).visibleFrame
        panel.setFrame(ClipboardPanelGeometry.panelFrame(visible: visible, panelHeight: preferences.panelHeight,
                                                         position: position, mouse: mouse), display: false)
    }

    private func reloadItems(preferredID: UUID? = nil) {
        items = repository.fetchAllClipboardItems(kind: nil)
        // 面板不可见时只标脏：收起状态下每次复制都渲染，等于白建上百个卡片视图
        guard panel.isVisible else { pendingReload = true; return }
        applyFilter(preferredID: preferredID)
    }

    private func applyFilter(preferredID: UUID? = nil) {
        // 检索/过滤纯逻辑见 ClipboardPanelSearch；此处不截断 —— filteredItems 持全部匹配项，屏幕卡片数由滑动窗口控制
        filteredItems = ClipboardPanelSearch.match(query: content.query, filter: content.filter,
                                                   repository: repository, items: items,
                                                   limit: max(1, preferences.maxItems))
        if let preferredID, let index = filteredItems.firstIndex(where: { $0.id == preferredID }) {
            selectedIndex = index
        } else if filteredItems.isEmpty {
            selectedIndex = -1
        } else {
            selectedIndex = min(max(selectedIndex, 0), filteredItems.count - 1)
        }
        content.render(items: filteredItems, selectedIndex: selectedIndex)
    }

    private var selectedItem: ClipboardItem? {
        selectedIndex >= 0 && selectedIndex < filteredItems.count ? filteredItems[selectedIndex] : nil
    }

    private func syncStackState() {
        content.updateStack(remaining: stack.remainingCount, total: stack.stackTotal)
        content.updatePermission(accessibilityGranted: stack.accessibilityGranted)
    }

    /// 面板级按键拦截（先于 responder chain）：搜索框非空时 ⌫ 交还字段编辑器，Tab 只切过滤、不进焦点环
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = flags.contains(.command), isShift = flags.contains(.shift)
        let isOption = flags.contains(.option), hasQuery = !content.query.isEmpty

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide(animated: true)
        case kVK_Delete, kVK_ForwardDelete:
            if hasQuery { return false }
            if isCommand, isShift { clearAll() } else if !isCommand { deleteSelected() } else { return false }
        case kVK_Tab:
            cycleFilter(reverse: isShift)   // ⇧Tab 反向循环过滤
        case kVK_ANSI_Comma:
            guard isCommand else { return false }
            hide(animated: false)
            onRequestSettings?()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            isCommand ? copySelected() : pasteSelected(asPlainText: isOption)
        // 单行横向流：←/→ 连续前后移动，↑/↓ 等价映射为前后
        case kVK_LeftArrow: moveSelection(-1)
        case kVK_RightArrow: moveSelection(1)
        case kVK_UpArrow: moveSelection(-1)
        case kVK_DownArrow: moveSelection(1)
        default:
            guard isCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch characters {
            case "d": togglePin()
            case "s": isShift ? clearStack() : pushSelectedToStack()
            case "1", "2", "3", "4", "5", "6", "7", "8", "9": quickPaste(Int(characters) ?? 0)
            default: return false
            }
        }
        return true
    }

    /// 方向键移动：单行卡片流上连续前后移动；无选中时向前落第一条、向后落最后一条
    private func moveSelection(_ delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let base = selectedIndex < 0 ? (delta > 0 ? -1 : 0) : selectedIndex
        var next = base + delta
        if next < 0 { next = filteredItems.count - 1 }
        if next >= filteredItems.count { next = 0 }
        selectedIndex = next
        content.updateSelection(next)
    }

    /// 过滤循环：⇧Tab 反向
    private func cycleFilter(reverse: Bool) {
        let all = ClipboardFilter.allCases
        let step = reverse ? all.count - 1 : 1
        content.selectFilter(all[(content.filter.rawValue + step) % all.count])
        applyFilter(preferredID: selectedItem?.id)
    }

    private func pasteSelected(asPlainText: Bool) {
        guard let item = selectedItem else { return }
        // 先收起面板让出 key，再走「写剪贴板 → 延迟 80ms → 合成 ⌘V」（见 ClipboardPaster）
        if paster.hasTargetApplication { hide(animated: false) }
        paster.paste(item, asPlainText: asPlainText) { [weak self] outcome in self?.handleOutcome(outcome) }
    }

    private func copySelected() {
        guard let item = selectedItem else { return }
        handleOutcome(paster.copyOnly(item))
    }

    private func quickPaste(_ number: Int) {
        guard preferences.quickPasteEnabled else {
            content.showHint("快速粘贴已关闭（可在剪贴板设置中开启）")
            return
        }
        let index = number - 1
        guard index >= 0, index < filteredItems.count else { return }
        selectedIndex = index
        content.updateSelection(index)
        pasteSelected(asPlainText: false)
    }

    private func handleOutcome(_ outcome: ClipboardPasteOutcome) {
        let message = outcome.message
        guard !message.isEmpty else { return }
        logger.info("剪贴板粘贴：\(message)")
        if panel.isVisible { content.showHint(message) } else { pendingHint = message }
    }

    private func togglePin() {
        guard let item = selectedItem else { return }
        repository.setClipboardItemPinned(id: item.id, isPinned: !item.isPinned)
        AppEvents.postClipboardChanged()
        reloadItems(preferredID: item.id)
    }

    private func deleteSelected() {
        guard let item = selectedItem else { return }
        repository.deleteClipboardItem(id: item.id)
        AppEvents.postClipboardChanged()
        reloadItems()
    }

    private func clearAll() {
        let removed = repository.clearClipboardItems(keepingPinned: true)
        logger.info("剪贴板历史已清空，删除 \(removed) 条（收藏保留）")
        AppEvents.postClipboardChanged()
        reloadItems()
        content.showHint("已清空历史（收藏项保留）")
    }

    private func pushSelectedToStack() {
        guard let item = selectedItem else { return }
        // 无辅助功能权限：不得静默，给出文案与跳转入口
        guard stack.push(id: item.id) else {
            content.showHint("缺少辅助功能权限，无法使用 Paste Stack，请前往系统设置授权")
            return
        }
        content.showHint("已加入 Paste Stack（第 \(stack.remainingCount) 项）")
    }

    private func clearStack() {
        stack.removeAll()
        content.showHint("Paste Stack 已清空")
    }

    func panelViewDidRequestCapture(_ view: ClipboardPanelView) { captureService.captureNow() }

    func panelView(_ view: ClipboardPanelView, didChangeQuery query: String) { applyFilter(preferredID: selectedItem?.id) }

    func panelView(_ view: ClipboardPanelView, didSelectFilter filter: ClipboardFilter) { applyFilter(preferredID: selectedItem?.id) }

    func panelView(_ view: ClipboardPanelView, didSelect index: Int) {
        guard index >= 0, index < filteredItems.count else { return }
        selectedIndex = index
        content.updateSelection(index)
    }

    func panelView(_ view: ClipboardPanelView, didActivate index: Int) {
        panelView(view, didSelect: index)
        pasteSelected(asPlainText: false)
    }

    func panelViewDidRequestOpenAccessibilitySettings(_ view: ClipboardPanelView) { stack.requestAccessibilityPermission() }
}
