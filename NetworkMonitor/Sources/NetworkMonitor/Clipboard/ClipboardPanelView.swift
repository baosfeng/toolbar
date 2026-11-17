import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板内容视图回调

/// 面板内容视图回调 — 所有动作都交给面板控制器执行，视图不持有业务依赖
@MainActor
protocol ClipboardPanelViewDelegate: AnyObject {
    /// 点击「采集当前剪贴板」（分支 A 的常驻入口）
    func panelViewDidRequestCapture(_ view: ClipboardPanelView)
    /// 搜索串变化（逐字过滤）
    func panelView(_ view: ClipboardPanelView, didChangeQuery query: String)
    /// 筛选芯片变化（增删一枚芯片或清空；纯逻辑口径见 ClipboardFilterToken）
    func panelView(_ view: ClipboardPanelView, didChangeFilterTokens tokens: [ClipboardFilterToken])
    /// 卡片被点选
    func panelView(_ view: ClipboardPanelView, didSelect index: Int)
    /// 卡片被双击（直接粘贴）
    func panelView(_ view: ClipboardPanelView, didActivate index: Int)
    /// 卡片右键「贴到屏幕」
    func panelView(_ view: ClipboardPanelView, didRequestPinAt index: Int)
    /// 卡片右键菜单其余指令（复制 / 粘贴为纯文本 / 收藏 / 删除）；按条目 ID 定位，不依赖卡片视图位置
    func panelView(_ view: ClipboardPanelView, didRequestMenuCommand command: ClipboardCardMenuCommand, itemID: UUID)
    /// 首次引导态被关闭（控制器据此写 ClipboardPreferences.hasGuidedClipboardAccess）
    func panelViewDidDismissGuide(_ view: ClipboardPanelView)
    /// 请求跳转辅助功能权限设置
    func panelViewDidRequestOpenAccessibilitySettings(_ view: ClipboardPanelView)
}


// MARK: - 面板窗口

/// 剪贴板面板窗口 — 非激活面板（不抢 App 激活态），并在窗口层拦截按键
///
/// 搜索框获得焦点后 ⌫ / ⌘D / ⌘1–⌘9 / Tab 会被 NSTextField 的字段编辑器吃掉，
/// 因此面板内快捷键统一在 keyDown / performKeyEquivalent 层拦截（控制器另有本地事件监听兜底）。
@MainActor
final class ClipboardPanel: NSPanel {
    /// keyDown 拦截（返回 true 表示已消费，不再进入 responder chain）
    var onKeyDown: ((NSEvent) -> Bool)?
    /// performKeyEquivalent 拦截（返回 true 表示已消费）
    var onPerformKeyEquivalent: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onPerformKeyEquivalent?(event) == true || super.performKeyEquivalent(with: event)
    }
}

// MARK: - 面板内容视图

/// 剪贴板面板内容视图 — 搜索框、过滤切换、卡片流、底部详情区、栈进度与权限入口
///
/// 布局（翻转坐标，自上而下）：工具条 32pt → 卡片区（弹性）→ 详情区（常驻，含 1pt 分隔线）→ 提示行 24pt。
/// 分段算术统一在 `ClipboardPanelLayout`（纯函数，TestRunner 覆盖）：面板高度变化只作用于卡片区，
/// 详情区与提示行各自定高，切条目时整块面板不会跳。
@MainActor
final class ClipboardPanelView: NSView, NSSearchFieldDelegate {

    /// 底部常驻按键提示（设计稿固定文案）
    static let keyHint = "↑↓ 选择 / ⌘ 粘贴 / ⌘1–9 直选 / Esc 收起 / ⌘P 暂停采集"

    /// 点击「采集已暂停」提示行要求切换暂停（由控制器挂到采集服务上）
    var onRequestTogglePause: (() -> Void)?

    weak var delegate: ClipboardPanelViewDelegate?

    /// 以下控件放宽为 internal：子视图构建与尺寸计算在 ClipboardPanelView+Subviews.swift
    let searchField = NSSearchField()
    /// 筛选芯片行（类型 / 来源 App / 日期，可叠加可单个删除；视图定义见 ClipboardFilterChipRowView）
    let chipRowView = ClipboardFilterChipRowView()
    let captureButton = NSButton()
    /// 工具条「?」快捷键帮助按钮
    let helpButton = NSButton()
    /// 首次引导态 / 快捷键帮助浮层（构建见 ClipboardPanelView+Subviews，视图定义见 ClipboardPanelOverlays）
    let guideView = ClipboardGuideView()
    let helpOverlay = ClipboardShortcutHelpOverlay()
    /// 底部件数计数（「N 条 · 收藏 M」）
    let countLabel = NSTextField(labelWithString: "")
    let stackLabel = NSTextField(labelWithString: "")
    let hintLabel = NSTextField(labelWithString: "")
    /// 「采集已暂停」提示行上的透明恢复热区（构建见 +Subviews，显隐由 revealPauseState 控制）
    let pauseResumeButton = NSButton()
    let accessibilityButton = NSButton()
    /// 卡片流（单行横向滚动 + 视图池 + 滑动窗口，见 ClipboardCardFlowView）
    let cardFlow = ClipboardCardFlowView()
    /// 工具条右段（采集与「?」之间）给 pinboard 圆点组预留位置：本批不做分组，只留槽位，
    /// 宽度由 ClipboardPanelLayout 统一分配，将来加板标签不必再动这层。
    static let reservesPinboardSlot = true
    /// 底部常驻详情区（选中条目的完整内容与元信息，见 ClipboardDetailStripView）
    let detailStrip = ClipboardDetailStripView()
    /// 两级材质的里层内衬与发丝分隔线层（视图口径与布局接线见 ClipboardPanelChrome.swift）
    let innerMaterial = ClipboardPanelInnerMaterialView()
    let separatorView = ClipboardPanelSeparatorView()

    /// 当前搜索串
    private(set) var query: String = ""
    /// 当前生效的筛选芯片（空数组 = 不过滤）
    private(set) var filterTokens: [ClipboardFilterToken] = []
    /// 「＋筛选」里来源 App 的候选数据源：视图不查库，由控制器在每次重载时按同一份数据灌入
    var filterSourceItems: [ClipboardItem] = []
    /// 当前选中下标
    private(set) var selectedIndex = -1

    /// 操作反馈（音效 / 触觉）— 构造器注入，未装配时用 `.silent`（快照与独立预览）
    /// 放宽 internal：ClipboardPanelView+Subviews.swift 的卡片流回调要在视图层接触觉
    let feedback: ClipboardFeedback

    override var isFlipped: Bool { true }

    /// 非激活态首次点击即生效（NSPanel 非激活面板的首次点击必须由视图放行）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 指定构造器：反馈按依赖注入，视图不自行取单例
    init(frame frameRect: NSRect, feedback: ClipboardFeedback = .silent) {
        self.feedback = feedback
        super.init(frame: frameRect)
        // 加视图顺序即层次：内衬最先（最底层）→ 分隔线 → 控件与卡片 → 浮层
        // 分隔线紧跟内衬：与改动前「父视图自绘、所有子视图压在其上」的层次一致，外观不回退
        buildInnerMaterial()
        buildSeparatorLayer()
        buildSearchField()
        buildChipRow()
        buildCaptureButton()
        buildHelpButton()
        buildFooter()
        buildCardFlow()
        buildDetailStrip()
        buildOverlays()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 对外状态更新

    /// 重建卡片流：交给卡片流视图做「视图池复用 + 滑动窗口」，此处不建任何卡片
    ///
    /// 详情区在同一次渲染里跟着换内容：过滤 / 搜索 / 删除都会改变「当前选中的是谁」。
    func render(items: [ClipboardItem], selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        cardFlow.render(items: items, selectedIndex: selectedIndex)
        let selected = selectedIndex >= 0 && selectedIndex < items.count ? items[selectedIndex] : nil
        detailStrip.update(item: selected)
    }

    /// 仅切换选中态（方向键移动时不重建卡片视图）
    func updateSelection(_ index: Int, item: ClipboardItem?) {
        selectedIndex = index
        cardFlow.updateSelection(index)
        detailStrip.update(item: item)
    }

    /// 更新栈进度（如「堆叠 2 条」；栈空时收起该标签，不占提示行）
    func updateStack(remaining: Int, total: Int) {
        guard remaining > 0 else {
            stackLabel.stringValue = ""
            stackLabel.isHidden = true
            needsLayout = true
            return
        }
        stackLabel.isHidden = false
        stackLabel.stringValue = "堆叠 \(remaining) 条"
        needsLayout = true
    }

    /// 更新辅助功能权限状态（无权限时高亮入口，不得静默）
    func updatePermission(accessibilityGranted: Bool) {
        applyPermissionStyle(accessibilityGranted: accessibilityGranted)
        needsLayout = true
    }

    /// 底部提示（降级路径必须让用户看见）
    func showHint(_ text: String) {
        hintLabel.stringValue = text
    }

    /// 透出暂停态：提示行常驻「采集已暂停（点此恢复）」，暂停时给一个覆盖提示行的恢复热区
    ///
    /// 与 `showHint` 的分工：那是临时提示（删除二次确认等），这是状态常驻；恢复按钮只在暂停时可点，
    /// 未暂停时隐藏，不抢提示行的点击。
    func revealPauseState(_ isPaused: Bool) {
        let text = ClipboardPauseLogic.footerHint(isPaused: isPaused, idleHint: Self.keyHint)
        hintLabel.stringValue = text
        hintLabel.textColor = isPaused ? .systemOrange : .secondaryLabelColor
        hintLabel.setAccessibilityLabel(isPaused ? "采集已暂停，点按或按 ⌘P 恢复采集" : text)
        pauseResumeButton.isHidden = !isPaused
        needsLayout = true
    }

    /// 暂停提示行的点击恢复
    @objc func resumeFromPauseBanner() { onRequestTogglePause?() }

    /// 替换全部筛选芯片（增删 / ⇧Tab 循环 / 清空都走这里）：视图只回传新数组，匹配交给控制器；
    /// 芯片宽度依赖字体，换完要重排工具条。
    func setFilterTokens(_ tokens: [ClipboardFilterToken]) {
        guard tokens != filterTokens else { return }
        filterTokens = tokens
        chipRowView.update(tokens: tokens)
        needsLayout = true
        delegate?.panelView(self, didChangeFilterTokens: tokens)
    }

    /// 让搜索框成为第一响应者（面板打开即可输入）
    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        delegate?.panelView(self, didChangeQuery: query)
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        let size = bounds.size
        let sections = ClipboardPanelLayout.sections(in: size)

        // 工具条与提示行的列宽分配在 ClipboardPanelLayout（纯函数，TestRunner 覆盖）
        let toolbar = ClipboardPanelLayout.toolbarMetrics(
            width: size.width,
            captureWidth: ceil(captureButton.fittingSize.width),
            chips: chipRowView.layoutChips())
        chipRowView.frame = NSRect(x: 0, y: 0, width: size.width, height: ClipboardPanelLayout.toolbarHeight)
        chipRowView.apply(toolbar.chipRow)
        searchField.frame = toolbar.search
        captureButton.frame = toolbar.capture
        helpButton.frame = toolbar.help

        let footer = ClipboardPanelLayout.footerMetrics(
            width: size.width,
            height: size.height,
            countWidth: countLabel.isHidden ? 0 : ceil(countLabel.intrinsicContentSize.width),
            stackWidth: stackLabel.isHidden ? 0 : ceil(stackLabel.intrinsicContentSize.width),
            permissionWidth: ceil(accessibilityButton.fittingSize.width))
        countLabel.frame = footer.count
        stackLabel.frame = footer.stack
        hintLabel.frame = footer.hint
        pauseResumeButton.frame = footer.hint
        accessibilityButton.frame = footer.permission

        cardFlow.frame = sections.cards
        detailStrip.frame = sections.detail
        // 引导态与卡片区同框（互斥显示）；帮助浮层铺满整个内容区，含工具条与提示行
        guideView.frame = sections.cards
        helpOverlay.frame = bounds

        layoutPanelChrome(separatorYs: sections.separatorYs)
    }

    // MARK: 动作（子视图构建与菜单分发见 ClipboardPanelView+Subviews.swift）

    @objc func captureNow() {
        delegate?.panelViewDidRequestCapture(self)
    }

    /// 「?」按钮：开合帮助浮层（再次点击收起）
    @objc func toggleShortcutHelp() {
        if isShortcutHelpVisible { hideShortcutHelp() } else { showShortcutHelp() }
    }

    @objc func openAccessibilitySettings() {
        delegate?.panelViewDidRequestOpenAccessibilitySettings(self)
    }
}