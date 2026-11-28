import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureFeedback
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
    /// 卡片被点选（click 带修饰键语义：无修饰 = 替换、⌘ = 切换、⇧ = 范围选）
    func panelView(_ view: ClipboardPanelView, didSelect index: Int, click: ClipboardSelectionModel.Click)
    /// 卡片被双击（直接粘贴）
    func panelView(_ view: ClipboardPanelView, didActivate index: Int)
    /// 卡片右键「贴到屏幕」
    func panelView(_ view: ClipboardPanelView, didRequestPinAt index: Int)
    /// 卡片右键菜单其余指令（复制 / 粘贴为纯文本 / 收藏 / 删除）；按条目 ID 定位，不依赖卡片视图位置。
    /// 「移到板…」另走下面的通道：子菜单项还要带目标板，不能只带条目 ID
    func panelView(_ view: ClipboardPanelView, didRequestMenuCommand command: ClipboardCardMenuCommand, itemID: UUID)
    /// 卡片右键「移到板…」（boardID 为 nil = 移出板；多选时作用于全部选中条目）
    func panelView(_ view: ClipboardPanelView, didRequestMoveToBoard boardID: UUID?, itemID: UUID)
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

/// 剪贴板面板内容视图 — 单行工具条 + 卡片流 + 编辑浮层 + 状态胶囊
///
/// 版式（翻转坐标，自上而下，对标 Paste 的底部横条）：
///
///     工具条 34pt：筛选芯片 → 搜索框 → 板胶囊（全部 / 各板 / ＋）→ 条数 →「?」→ 采集图标
///     卡片区（弹性）：单行横向滚动，卡片尺寸随卡片区高度自适应
///
/// **没有常驻详情区、没有常驻提示行**：完整内容由「空格预览」浮层承担，编辑（⌘E / ⌘N）
/// 时才把详情区当成一块浮层放到面板底部，暂停 / 权限 / 提示之类走底部状态胶囊。
/// 分段算术统一在 ClipboardPanelLayout（纯函数，TestRunner 覆盖）。
@MainActor
final class ClipboardPanelView: NSView, NSSearchFieldDelegate {

    /// 编辑取消 / 保存后的回落提示（空闲时不再有常驻键位条，所以只写最常用的四条）
    static let keyHint = "↑↓ 选择 / ⌘1–9 直选 / 空格预览 / Esc 收起"

    /// 点击「采集已暂停」胶囊要求切换暂停（由控制器挂到采集服务上）
    var onRequestTogglePause: (() -> Void)?

    weak var delegate: ClipboardPanelViewDelegate?

    /// 以下控件放宽为 internal：子视图构建与尺寸计算在 ClipboardPanelView+Subviews.swift
    let searchField = NSSearchField()
    /// 筛选芯片行（类型 / 来源 App / 日期，可叠加可单个删除；与搜索框共用工具条）
    let chipRowView = ClipboardFilterChipRowView()
    /// 板胶囊（全部 / 各板 / ＋新建；工具条里紧跟搜索框）
    let boardRowView = ClipboardBoardRowView()
    /// 板胶囊的两个出口（控制器在 ClipboardPanelController 与 ClipboardBoardCoordinator 里接）
    var onSelectBoard: ((UUID?) -> Void)?
    var onRequestCreateBoard: ((NSRect) -> Void)?
    /// 「采集当前剪贴板」（纯图标 + tooltip）
    let captureButton = NSButton()
    /// 工具条「?」快捷键帮助按钮
    let helpButton = NSButton()
    /// 首次引导态 / 快捷键帮助浮层（构建见 ClipboardPanelView+Subviews，视图定义见 ClipboardPanelOverlays）
    let guideView = ClipboardGuideView()
    let helpOverlay = ClipboardShortcutHelpOverlay()
    /// 卡片数 / 收藏数（工具条右端的状态文本，不是按钮）
    let countLabel = NSTextField(labelWithString: "")
    /// 卡片流（单行横向滚动 + 视图池 + 滑动窗口，见 ClipboardCardFlowView）
    let cardFlow = ClipboardCardFlowView()
    /// 底部状态胶囊（暂停 / 权限 / 提示 / 多选 / 栈；浮在卡片之上，不占布局高度）
    let statusBand = ClipboardPanelStatusBand()
    /// 编辑浮层（只在 ⌘E / ⌘N 期间出现，覆盖卡片区下沿；平时隐藏）
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

    /// 操作反馈（音效 / 触觉）— 构造器注入，未装配时用 .silent（快照与独立预览）
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
        buildInnerMaterial()
        buildSeparatorLayer()
        buildSearchField()
        buildChipRow()
        buildBoardRow()
        buildCaptureButton()
        buildHelpButton()
        buildCountLabel()
        buildCardFlow()
        buildDetailStrip()
        buildStatusBand()
        buildOverlays()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 对外状态更新

    /// 重建卡片流：交给卡片流视图做「视图池复用 + 滑动窗口」，此处不建任何卡片
    func render(items: [ClipboardItem], selectedIndex: Int, selectedIDs: Set<UUID>? = nil) {
        self.selectedIndex = selectedIndex
        let ids = selectedIDs ?? ClipboardCardFlowView.singleSelection(items: items, index: selectedIndex)
        cardFlow.render(items: items, selectedIndex: selectedIndex, selectedIDs: ids)
        // 多选摘要改由底部状态胶囊承担（详情区已退成编辑浮层）
        statusBand.updateMultiSelection(count: ids.count)
    }

    /// 仅切换选中态（方向键移动时不重建卡片视图）
    func updateSelection(_ index: Int, item: ClipboardItem?, selectedIDs: Set<UUID>? = nil) {
        _ = item
        selectedIndex = index
        let ids = selectedIDs ?? ClipboardCardFlowView.singleSelection(items: cardFlow.items, index: index)
        cardFlow.updateSelection(index, selectedIDs: ids)
        statusBand.updateMultiSelection(count: ids.count)
    }

    /// 多选态：底部胶囊改成「已选 N 条」摘要（单条详情在空格预览里看）
    func updateMultiSelection(count: Int) {
        statusBand.updateMultiSelection(count: count)
    }

    /// 更新栈进度（如「堆叠 2 条」；栈空时收起，不占位）
    func updateStack(remaining: Int, total: Int) {
        _ = total
        statusBand.updateStack(remaining: remaining)
    }

    /// 更新辅助功能权限状态（无权限时高亮入口，不得静默）
    func updatePermission(accessibilityGranted: Bool) {
        statusBand.updatePermission(granted: accessibilityGranted)
    }

    /// 临时提示（降级路径必须让用户看见）：底部胶囊显示 4 秒后自动收起
    func showHint(_ text: String) {
        statusBand.showHint(text)
    }

    /// 透出暂停态：胶囊常驻「采集已暂停（点此恢复）」，定时暂停带出截止时刻
    func revealPauseState(_ isPaused: Bool, until pausedUntil: Date = .distantPast, now: Date = Date()) {
        let text = ClipboardPauseLogic.footerHint(isPaused: isPaused, pausedUntil: pausedUntil,
                                                  now: now, idleHint: Self.keyHint)
        statusBand.revealPause(isPaused, text: isPaused ? text : "")
        statusBand.setAccessibilityLabel(isPaused ? "采集已暂停，点按或按 ⌘P 恢复采集" : "面板状态")
    }

    /// 暂停胶囊的点击恢复
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
        // 高亮只跟搜索态走：查询清空后立即回落无高亮（不等下一次重排）
        cardFlow.setHighlightQuery(query)
        delegate?.panelView(self, didChangeQuery: query)
    }

    /// 外部（控制器 / 快照）改写搜索串：同步搜索框、卡片高亮与查询态
    func setQuery(_ text: String) {
        guard searchField.stringValue != text else { return }
        searchField.stringValue = text
        query = text
        cardFlow.setHighlightQuery(text)
        delegate?.panelView(self, didChangeQuery: text)
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        let size = bounds.size
        let sections = ClipboardPanelLayout.sections(in: size)

        // 工具条一行的列宽分配在 ClipboardPanelLayout（纯函数，TestRunner 覆盖）
        let toolbar = ClipboardPanelLayout.toolbarMetrics(
            width: size.width,
            countWidth: countLabel.isHidden ? 0 : Self.measuredWidth(of: countLabel),
            chips: chipRowView.layoutChips(),
            boardChips: boardRowView.layoutChips())
        chipRowView.frame = sections.toolbar
        chipRowView.apply(toolbar.chipRow)
        boardRowView.frame = sections.toolbar
        layoutBoardRow(toolbar.boardRow)
        searchField.frame = toolbar.search
        countLabel.frame = toolbar.count
        helpButton.frame = toolbar.help
        captureButton.frame = toolbar.capture

        cardFlow.frame = sections.cards
        // 详情区退成编辑浮层：贴面板底、覆盖卡片区下沿，只在编辑态出现
        let detailHeight = ClipboardDetailStrip.totalHeight
        detailStrip.frame = NSRect(x: 0, y: max(0, size.height - detailHeight),
                                   width: size.width, height: detailHeight)
        // 状态胶囊贴面板底、左右各留一个内边距（浮在卡片之上，不占分段高度）
        statusBand.frame = NSRect(x: ClipboardPanelLayout.paddingX,
                                  y: max(0, size.height - ClipboardPanelStatusBand.height - 2),
                                  width: max(0, size.width - ClipboardPanelLayout.paddingX * 2),
                                  height: ClipboardPanelStatusBand.height)
        // 引导态与卡片区同框（互斥显示）；帮助浮层铺满整个内容区，含工具条
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

    /// 单行文本的实测宽（按字体量，不靠 intrinsicContentSize：带截断模式的标签会给出偏小的值）
    static func measuredWidth(of label: NSTextField) -> CGFloat {
        let font = label.font ?? NSFont.systemFont(ofSize: 10.5)
        // +6：NSTextField 的 cell 自带一点横向内缩，按裸字宽给框会让「·」被省略号顶掉
        return ceil((label.stringValue as NSString).size(withAttributes: [.font: font]).width) + 6
    }
}
