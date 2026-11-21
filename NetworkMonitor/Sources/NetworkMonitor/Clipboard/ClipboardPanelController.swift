import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureFeedback
import NetworkMonitorUI

// MARK: - 面板控制器

/// 剪贴板面板控制器 — 面板生命周期、定位、动画、按键拦截与动作执行
@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate, ClipboardPanelViewDelegate {

    /// 面板展开 / 收起动效口径（设计规格 §3 B2：0.18s、展开位移 14pt；动效本体走 MotionKit）
    private enum Motion {
        static let duration: TimeInterval = 0.18
        static let offsetY: CGFloat = 14
    }

    private let panel: ClipboardPanel
    let content: ClipboardPanelView
    let repository: any ClipboardRepository
    let captureService: any ClipboardCaptureService   // 放宽为 internal：暂停切换与状态同步在 ClipboardPauseControl
    let paster: ClipboardPaster    // 反馈接线见 +Feedback
    let stack: PasteStackController    // 栈动作见 +Stack
    let boards: ClipboardBoardCoordinator    // 板标签状态机（见 ClipboardBoardCoordinator）
    let preferences: ClipboardPreferences    // 首次引导 / 栈 / 识别扩展文件都要读写
    let logger: LoggingService
    let feedback: ClipboardFeedback    // 组合根注入，+Keyboard / +Feedback 也用
    let onRequestSettings: (() -> Void)?
    var onRequestPin: ((ClipboardItem) -> Void)?    // 贴到屏幕（组合根接到截图链路）

    var items: [ClipboardItem] = []    // 放宽 internal：首次引导判定要看历史是否为空
    var filteredItems: [ClipboardItem] = []    // 拼图扩展文件按索引取条目
    /// 多选状态（集合 + 焦点）：下标由焦点派生，见 ClipboardSelectionActions
    var selection = ClipboardSelectionModel()
    private var pendingHint: String?
    private var pendingReload = false
    var singleDeleteConfirm = ClipboardDeleteConfirm()
    var clearAllConfirm = ClipboardDeleteConfirm()
    var multiDeleteConfirm = ClipboardDeleteConfirm()   // 批量删除独立确认，不与单条串味
    var previewWindow: ClipboardPreviewWindow?   // 预览浮层（自绘，见 ClipboardPreviewLayer）
    nonisolated(unsafe) private var localKeyMonitor: Any?
    nonisolated(unsafe) private var clipboardObserver: NSObjectProtocol?
    nonisolated(unsafe) var ocrObserver: NSObjectProtocol?   // 识别结果订阅与刷新在 ClipboardOCRPanel.swift

    init(repository: any ClipboardRepository,
         boardRepository: (any ClipboardBoardRepository)?,
         captureService: any ClipboardCaptureService,
         paster: ClipboardPaster, stack: PasteStackController, feedback: ClipboardFeedback,
         onRequestSettings: (() -> Void)? = nil,
         preferences: ClipboardPreferences, logger: LoggingService = AppContext.shared.logger) {
        self.repository = repository; self.captureService = captureService
        self.boards = ClipboardBoardCoordinator(repository: boardRepository, logger: logger)
        self.paster = paster; self.stack = stack; self.feedback = feedback
        self.onRequestSettings = onRequestSettings
        self.preferences = preferences; self.logger = logger
        let rect = NSRect(x: 0, y: 0, width: 640, height: 260)
        self.panel = ClipboardPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        self.content = ClipboardPanelView(frame: rect, feedback: feedback)   // 选中切换的触觉由卡片流回调直接打
        super.init()
        configurePanel()
        observeClipboardChanges()
        observeOCRTextReady()
        stack.onStateChange = { [weak self] in self?.syncStackState() }
        // 栈推进（⌘V 贴出队首）单独反馈：onStateChange 还覆盖入栈 / 重载 / 清空，不能一律打触觉
        stack.onAdvance = { [weak self] in self?.reportStackAdvanced() }
        wireBoardRow()   // 板标签接线（动作体见 ClipboardBoardCoordinator）
    }

    nonisolated deinit {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let clipboardObserver { NotificationCenter.default.removeObserver(clipboardObserver) }
        if let ocrObserver { NotificationCenter.default.removeObserver(ocrObserver) }
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
        boards.reload()
        stack.reloadStack()
        // 分支 A / B 通用：打开瞬间读一次（changeCount 未变则静默返回，不重复读）
        captureService.captureNow()
        if let hint = pendingHint { content.showHint(hint); pendingHint = nil }
        expireTimedPauseIfNeeded()   // 定时暂停到点即恢复（宿主节拍之外的补位）
        syncPauseState()   // 暂停态最后落定：不被上一次的临时提示盖掉
        positionPanel()
        let finalFrame = panel.frame
        // 起始态先进 MotionKit：允许动效是「透明 + 下移 14pt」，减弱动态效果时直接落终态
        MotionKit.stageWindowEntrance(panel, fromOffsetY: Motion.offsetY, toFrame: finalFrame)
        panel.makeKeyAndOrderFront(nil)
        content.focusSearchField()
        // 动画在 makeKeyAndOrderFront 之后执行：位移回落与淡入都发生在面板已成为 key 之后
        MotionKit.fadeIn(window: panel, toFrame: finalFrame, duration: Motion.duration)
        // 展开提示音（默认关；设置页「面板展开收起」一行开）。
        // 放在最后：先让面板出来再响，听感上才是「打开」而不是「点击」
        feedback.sound.play(.panelToggle)
    }

    /// 收起面板；animated=false 用于粘贴路径 —— 立即 orderOut 让出 key，合成的 ⌘V 才落得到目标 App
    func hide(animated: Bool) {
        guard panel.isVisible else { return }
        // 帮助浮层与预览浮层都不跨次留存：收起面板时一并关掉
        content.hideShortcutHelp(); closePreview()
        clearDeleteConfirmHint()
        _ = collapseMultiSelectionIfNeeded()   // 多选不跨次留存：收回到焦点单条，下次打开仍停在上次那条（返回值只有 Esc 路径关心）
        // 收起后不再需要缩略图：丢弃在途回调（已入队任务允许跑完，缓存与磁盘文件不删）
        ClipboardThumbnailLoader.shared.cancelAll()
        // animated=false 不套动效：立即 orderOut 让出 key（粘贴路径依赖这一点）
        guard animated else { panel.orderOut(nil); return }
        // 收起提示音：只在「用户主动收起」这条路上响，粘贴路径（animated=false）不响
        feedback.sound.play(.panelToggle)
        MotionKit.fadeOut(window: panel, duration: Motion.duration) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) { hide(animated: true) }

    /// 定位：几何计算见 ClipboardPanelGeometry（目标屏 visibleFrame 底部；高度夹紧口径在偏好层）
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
        content.filterSourceItems = items
        filteredItems = ClipboardPanelSearch.match(query: content.query, tokens: content.filterTokens,
                                                   repository: repository, items: boards.scoped(items),
                                                   limit: max(1, preferences.maxItems))
        restoreSelection(preferredID: preferredID)
        content.render(items: filteredItems, selectedIndex: selectedIndex, selectedIDs: selection.ids)
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

    func panelViewDidRequestCapture(_ view: ClipboardPanelView) { captureNowUnlessPaused() }

    func panelView(_ view: ClipboardPanelView, didChangeQuery query: String) { applyFilter(preferredID: selectedItem?.id) }

    func panelView(_ view: ClipboardPanelView, didChangeFilterTokens tokens: [ClipboardFilterToken]) { applyFilter(preferredID: selectedItem?.id) }

    func panelView(_ view: ClipboardPanelView, didSelect index: Int, click: ClipboardSelectionModel.Click) {
        applySelectionClick(at: index, click: click)
    }

    func panelView(_ view: ClipboardPanelView, didActivate index: Int) {
        // 双击 = 直接粘贴这一条：先把它落成焦点单条，粘贴永远只作用于一条
        selectSingle(at: index)
        pasteSelected(asPlainText: false)
    }

    func panelViewDidRequestOpenAccessibilitySettings(_ view: ClipboardPanelView) { stack.requestAccessibilityPermission() }
}