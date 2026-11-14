import AppKit
import NetworkMonitorCore

// MARK: - 面板控制器

/// 剪贴板面板控制器 — 面板生命周期、定位、动画、按键拦截与动作执行
@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate, ClipboardPanelViewDelegate {

    /// 面板展开 / 收起动效口径（设计规格 §3 B2：0.18s、展开位移 14pt）
    ///
    /// 动效本体一律走 `MotionKit`（跟随「减弱动态效果」），本处只留时长与位移两个数值。
    private enum Motion {
        static let duration: TimeInterval = 0.18
        static let offsetY: CGFloat = 14
    }

    private let panel: ClipboardPanel
    let content: ClipboardPanelView
    let repository: any ClipboardRepository
    private let captureService: any ClipboardCaptureService
    /// 放宽 internal：复制 / 粘贴 / 收藏 / 栈推进的反馈在 ClipboardPanelController+Feedback.swift
    let paster: ClipboardPaster
    /// 放宽 internal：Paste Stack 动作在 ClipboardPanelController+Stack.swift，需访问 stack
    let stack: PasteStackController
    /// 放宽 internal：首次引导与 Paste Stack 扩展文件要读写偏好
    let preferences: ClipboardPreferences
    /// 放宽 internal：贴图扩展文件要写日志
    let logger: LoggingService
    /// 操作反馈（音效 + 触觉）— 组合根注入，面板视图与控制器共用同一份
    let feedback: ClipboardFeedback
    /// ⌘, 打开剪贴板设置（组合根注入，复用既有设置窗打开路径）
    /// 放宽 internal：按键拦截在 ClipboardPanelController+Keyboard.swift
    let onRequestSettings: (() -> Void)?
    /// 把某条历史贴到屏幕（组合根注入到截图链路）
    var onRequestPin: ((ClipboardItem) -> Void)?

    /// 放宽 internal：首次引导判定要看「历史是否为空」
    var items: [ClipboardItem] = []
    /// 放宽为 internal：贴图扩展文件要按索引取条目
    var filteredItems: [ClipboardItem] = []
    var selectedIndex = -1
    private var pendingHint: String?
    private var pendingReload = false
    var singleDeleteConfirm = ClipboardDeleteConfirm()
    var clearAllConfirm = ClipboardDeleteConfirm()
    nonisolated(unsafe) private var localKeyMonitor: Any?
    nonisolated(unsafe) private var clipboardObserver: NSObjectProtocol?

    init(repository: any ClipboardRepository, captureService: any ClipboardCaptureService,
         paster: ClipboardPaster, stack: PasteStackController, feedback: ClipboardFeedback,
         onRequestSettings: (() -> Void)? = nil,
         preferences: ClipboardPreferences, logger: LoggingService = AppContext.shared.logger) {
        self.repository = repository; self.captureService = captureService
        self.paster = paster; self.stack = stack; self.feedback = feedback
        self.onRequestSettings = onRequestSettings
        self.preferences = preferences; self.logger = logger
        let rect = NSRect(x: 0, y: 0, width: 640, height: 260)
        self.panel = ClipboardPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        // 反馈按构造器注入交给面板视图：选中切换的触觉由卡片流回调直接打，不经控制器转一圈
        self.content = ClipboardPanelView(frame: rect, feedback: feedback)
        super.init()
        configurePanel()
        observeClipboardChanges()
        stack.onStateChange = { [weak self] in self?.syncStackState() }
        // 栈推进（⌘V 贴出队首）单独反馈：onStateChange 还覆盖入栈 / 重载 / 清空，不能一律打触觉
        stack.onAdvance = { [weak self] in self?.reportStackAdvanced() }
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

        // 面板底（弹窗层的玻璃）：macOS 26+ 且玻璃开启时走 NSGlassEffectView，
        // 否则回落原 `.hudWindow` 材质路径（视觉不塌）。圆角恒 14pt。
        let background = makePanelBackground()
        content.frame = background.bounds
        background.addSubview(content)
        panel.contentView = background

        // 本地事件监听：先于 responder chain 拿到按键（搜索框聚焦时字段编辑器会吃掉 ⌫ / ⌘D / Tab）
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    /// 造剪贴板面板的底 —— 弹窗层玻璃的落点
    ///
    /// - Returns: 玻璃（26+ 且开关打开）或原 `.hudWindow` 材质视图；两者都带 14pt 圆角
    private func makePanelBackground() -> NSView {
        let frame = NSRect(origin: .zero, size: panel.frame.size)
        if let glass = GlassStyle.makePanelGlass(interactive: false) {
            glass.frame = frame
            glass.autoresizingMask = [.width, .height]
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 14
            glass.layer?.masksToBounds = true
            return glass
        }
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        return effect
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
        // 起始态先进 MotionKit：允许动效是「透明 + 下移 14pt」，减弱动态效果时直接落终态
        MotionKit.stageWindowEntrance(panel, fromOffsetY: Motion.offsetY, toFrame: finalFrame)
        panel.makeKeyAndOrderFront(nil)
        content.focusSearchField()
        // 动画在 makeKeyAndOrderFront 之后执行：位移回落与淡入都发生在面板已成为 key 之后
        MotionKit.fadeIn(window: panel, toFrame: finalFrame, duration: Motion.duration)
    }

    /// 收起面板；animated=false 用于粘贴路径 —— 立即 orderOut 让出 key，合成的 ⌘V 才落得到目标 App
    func hide(animated: Bool) {
        guard panel.isVisible else { return }
        // 帮助浮层不跨次留存：收起面板时一并关掉，下次打开是干净的面板
        content.hideShortcutHelp()
        clearDeleteConfirmHint()
        // 收起后不再需要缩略图：丢弃在途回调（已入队任务允许跑完，缓存与磁盘文件不删）
        ClipboardThumbnailLoader.shared.cancelAll()
        // animated=false 不套动效：立即 orderOut 让出 key（粘贴路径依赖这一点）
        guard animated else { panel.orderOut(nil); return }
        MotionKit.fadeOut(window: panel, duration: Motion.duration) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) { hide(animated: true) }

    /// 定位：几何计算见 ClipboardPanelGeometry（目标屏 visibleFrame 底部）
    private func positionPanel() {
        let mouse = NSEvent.mouseLocation, position = preferences.panelPosition
        let visible = ClipboardPanelGeometry.targetScreen(position: position, mouse: mouse).visibleFrame
        panel.setFrame(ClipboardPanelGeometry.panelFrame(visible: visible, panelHeight: preferences.panelHeight,
                                                         position: position, mouse: mouse), display: false)
    }

    func reloadItems(preferredID: UUID? = nil) {
        items = repository.fetchAllClipboardItems(kind: nil)
        // 面板不可见时只标脏：收起状态下每次复制都渲染，等于白建上百个卡片视图
        guard panel.isVisible else { pendingReload = true; return }
        applyFilter(preferredID: preferredID)
    }

    /// 放宽 internal：过滤循环在 ClipboardPanelController+Keyboard.swift
    func applyFilter(preferredID: UUID? = nil) {
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
        content.updateCounts(total: filteredItems.count, pinned: filteredItems.filter { $0.isPinned }.count)
        refreshGuideState()
    }

    var selectedItem: ClipboardItem? {
        selectedIndex >= 0 && selectedIndex < filteredItems.count ? filteredItems[selectedIndex] : nil
    }

    private func syncStackState() {
        content.updateStack(remaining: stack.remainingCount, total: stack.stackTotal)
        content.updatePermission(accessibilityGranted: stack.accessibilityGranted)
    }


    func pasteSelected(asPlainText: Bool) {
        guard let item = selectedItem else { return }
        // 先收起面板让出 key，再走「写剪贴板 → 延迟 80ms → 合成 ⌘V」（见 ClipboardPaster）
        if paster.hasTargetApplication { hide(animated: false) }
        paster.paste(item, asPlainText: asPlainText) { [weak self] outcome in
            self?.reportPasteOutcome(outcome)
        }
    }

    func copySelected() {
        guard let item = selectedItem else { return }
        reportCopyOutcome(paster.copyOnly(item))
    }

    /// 放宽 internal：复制 / 粘贴的反馈接线在 ClipboardPanelController+Feedback.swift
    func handleOutcome(_ outcome: ClipboardPasteOutcome) {
        let message = outcome.message
        guard !message.isEmpty else { return }
        logger.info("剪贴板粘贴：\(message)")
        if panel.isVisible { content.showHint(message) } else { pendingHint = message }
    }

    func togglePin() {
        guard let item = selectedItem else { return }
        let target = !item.isPinned
        repository.setClipboardItemPinned(id: item.id, isPinned: target)
        // 反馈只在此处打一次：卡片刷新只重建视图，不再重复触发
        reportPinToggled(to: target)
        AppEvents.postClipboardChanged()
        reloadItems(preferredID: item.id)
    }

    // 删除 / 清空的动作体见 ClipboardPanelController+Delete.swift（含二次确认状态机）

    func panelViewDidRequestCapture(_ view: ClipboardPanelView) { captureService.captureNow() }

    func panelView(_ view: ClipboardPanelView, didChangeQuery query: String) { applyFilter(preferredID: selectedItem?.id) }

    func panelView(_ view: ClipboardPanelView, didSelectFilter filter: ClipboardFilter) { applyFilter(preferredID: selectedItem?.id) }

    func panelView(_ view: ClipboardPanelView, didSelect index: Int) {
        guard index >= 0, index < filteredItems.count else { return }
        selectedIndex = index
        content.updateSelection(index)
        clearDeleteConfirmHint()
    }

    func panelView(_ view: ClipboardPanelView, didActivate index: Int) {
        panelView(view, didSelect: index)
        pasteSelected(asPlainText: false)
    }

    func panelViewDidRequestOpenAccessibilitySettings(_ view: ClipboardPanelView) { stack.requestAccessibilityPermission() }
}
