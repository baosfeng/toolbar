import AppKit
import NetworkMonitorCore

// MARK: - 过滤类型

/// 面板过滤（Tab 循环切换：全部 → 文本 → 图片 → 收藏）
enum ClipboardFilter: Int, CaseIterable {
    case all
    case text
    case image
    case pinned

    /// 中文名称（过滤控件文案与无障碍描述）
    var label: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .pinned: return "收藏"
        }
    }

    /// 条目是否命中该过滤
    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text || item.kind == .rtf
        case .image: return item.kind == .image
        case .pinned: return item.isPinned
        }
    }
}

// MARK: - 面板内容视图回调

/// 面板内容视图回调 — 所有动作都交给面板控制器执行，视图不持有业务依赖
@MainActor
protocol ClipboardPanelViewDelegate: AnyObject {
    /// 点击「采集当前剪贴板」（分支 A 的常驻入口）
    func panelViewDidRequestCapture(_ view: ClipboardPanelView)
    /// 搜索串变化（逐字过滤）
    func panelView(_ view: ClipboardPanelView, didChangeQuery query: String)
    /// 过滤切换
    func panelView(_ view: ClipboardPanelView, didSelectFilter filter: ClipboardFilter)
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

/// 剪贴板面板内容视图 — 搜索框、过滤切换、卡片流、栈进度与权限入口
///
/// 布局（翻转坐标，自上而下）：工具条 32pt（搜索 + 过滤 + 采集）→ 卡片区（面板高 − 32 − 24）→ 提示行 24pt。
/// 左右内边距统一 10pt；卡片区高度随面板高度自适应，保证卡片始终垂直居中。
@MainActor
final class ClipboardPanelView: NSView, NSSearchFieldDelegate {

    /// 布局口径（设计规格：内边距 10、工具条 32、提示行 24、搜索框弹性 300–420）
    private enum Metrics {
        static let padding: CGFloat = 10
        static let toolbarHeight: CGFloat = 32
        static let footerHeight: CGFloat = 24
        static let controlHeight: CGFloat = 24
        static let searchMinWidth: CGFloat = 300
        static let searchMaxWidth: CGFloat = 420
        static let filterWidth: CGFloat = 160
        /// 「?」快捷键帮助按钮宽度（纯图标按钮）
        static let helpButtonWidth: CGFloat = 24
        static let gap: CGFloat = 8
        static let footerTextHeight: CGFloat = 16
    }

    /// 底部常驻按键提示（设计稿固定文案）
    static let keyHint = "↑↓ 选择 / ⌘ 粘贴 / ⌘1–9 直选 / Esc 收起"

    weak var delegate: ClipboardPanelViewDelegate?

    /// 以下控件放宽为 internal：子视图构建与尺寸计算在 ClipboardPanelView+Subviews.swift
    let searchField = NSSearchField()
    let filterControl = NSSegmentedControl()
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
    let accessibilityButton = NSButton()
    /// 卡片流（单行横向滚动 + 视图池 + 滑动窗口，见 ClipboardCardFlowView）
    let cardFlow = ClipboardCardFlowView()
    /// 两级材质的里层内衬与发丝分隔线层（视图口径与布局接线见 ClipboardPanelChrome.swift）
    let innerMaterial = ClipboardPanelInnerMaterialView()
    let separatorView = ClipboardPanelSeparatorView()

    /// 当前搜索串
    private(set) var query: String = ""
    /// 当前过滤
    private(set) var filter: ClipboardFilter = .all
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
        buildFilterControl()
        buildCaptureButton()
        buildHelpButton()
        buildFooter()
        buildCardFlow()
        buildOverlays()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 对外状态更新

    /// 重建卡片流：交给卡片流视图做「视图池复用 + 滑动窗口」，此处不建任何卡片
    func render(items: [ClipboardItem], selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        cardFlow.render(items: items, selectedIndex: selectedIndex)
    }

    /// 仅切换选中态（方向键移动时不重建卡片视图）
    func updateSelection(_ index: Int) {
        selectedIndex = index
        cardFlow.updateSelection(index)
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

    /// 程序化切换过滤（Tab 循环）
    func selectFilter(_ filter: ClipboardFilter) {
        self.filter = filter
        filterControl.selectedSegment = filter.rawValue
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
        let width = bounds.width
        let height = bounds.height
        let padding = Metrics.padding

        layoutToolbar(width: width)
        layoutFooter(width: width, height: height)

        // 卡片区 = 面板高 − 工具条 − 提示行（左右 10pt，上下不留白，由卡片流自身垂直居中）
        let cardsHeight = max(0, height - Metrics.toolbarHeight - Metrics.footerHeight)
        let cardsFrame = NSRect(x: padding, y: Metrics.toolbarHeight,
                                width: max(0, width - padding * 2), height: cardsHeight)
        cardFlow.frame = cardsFrame
        // 引导态与卡片区同框（互斥显示）；帮助浮层铺满整个内容区，含工具条与提示行
        guideView.frame = cardsFrame
        helpOverlay.frame = bounds

        layoutPanelChrome(toolbarHeight: Metrics.toolbarHeight, footerHeight: height - Metrics.footerHeight)
    }

    /// 工具条：搜索框弹性 300–420、类型过滤、右侧「采集当前剪贴板」
    private func layoutToolbar(width: CGFloat) {
        let padding = Metrics.padding
        let controlY = (Metrics.toolbarHeight - Metrics.controlHeight) / 2
        let captureWidth = max(96, ceil(captureButton.fittingSize.width))
        // 「?」按钮固定宽，从搜索框可用宽度里让出来（两处间距都要扣）；采集按钮仍贴右边缘
        let helpWidth = Metrics.helpButtonWidth
        let searchWidth = min(Metrics.searchMaxWidth,
                              max(Metrics.searchMinWidth,
                                  width - padding * 2 - captureWidth - helpWidth
                                      - Metrics.filterWidth - Metrics.gap * 3))
        searchField.frame = NSRect(x: padding, y: controlY,
                                   width: searchWidth, height: Metrics.controlHeight)
        filterControl.frame = NSRect(x: padding + searchWidth + Metrics.gap, y: controlY,
                                     width: Metrics.filterWidth, height: Metrics.controlHeight)
        captureButton.frame = NSRect(x: width - padding - captureWidth, y: controlY,
                                     width: captureWidth, height: Metrics.controlHeight)
        helpButton.frame = NSRect(x: width - padding - captureWidth - Metrics.gap - helpWidth,
                                  y: controlY, width: helpWidth, height: Metrics.controlHeight)
    }

    /// 提示行：自左向右为「件数计数 → 栈进度 → 按键提示」，最右是「辅助功能权限」入口
    ///
    /// 宽度不足时先压缩提示行文案（计数与栈进度按内容定宽、不截断成半个）；左段确实占满
    /// 整行时才退到紧凑布局：栈进度让位，计数与提示共享剩余空间，保证窄面板下计数不消失。
    private func layoutFooter(width: CGFloat, height: CGFloat) {
        let padding = Metrics.padding
        let textY = height - Metrics.footerHeight + (Metrics.footerHeight - Metrics.footerTextHeight) / 2
        let permissionWidth = max(72, ceil(accessibilityButton.fittingSize.width))
        let permissionX = width - padding - permissionWidth
        accessibilityButton.frame = NSRect(x: permissionX, y: textY,
                                           width: permissionWidth, height: Metrics.footerTextHeight)

        let countWidth = countLabel.isHidden ? 0 : min(160, ceil(countLabel.intrinsicContentSize.width))
        let stackWidth = stackLabel.isHidden ? 0 : min(120, ceil(stackLabel.intrinsicContentSize.width))
        let hintRight = permissionX - Metrics.gap
        let countX = padding
        let stackX = countX + (countWidth > 0 ? countWidth + Metrics.gap : 0)
        let hintX = stackX + (stackWidth > 0 ? stackWidth + Metrics.gap : 0)

        if hintX >= hintRight {
            // 紧凑布局：栈进度让位（栈状态仍由卡片角标与面板提示兜底）
            if countWidth > 0 {
                countLabel.frame = NSRect(x: countX, y: textY, width: countWidth, height: Metrics.footerTextHeight)
            }
            stackLabel.frame = NSRect(x: stackX, y: textY, width: 0, height: Metrics.footerTextHeight)
            hintLabel.frame = NSRect(x: stackX, y: textY,
                                     width: max(0, hintRight - stackX), height: Metrics.footerTextHeight)
            return
        }
        if countWidth > 0 {
            countLabel.frame = NSRect(x: countX, y: textY, width: countWidth, height: Metrics.footerTextHeight)
        }
        stackLabel.frame = NSRect(x: stackX, y: textY, width: stackWidth, height: Metrics.footerTextHeight)
        hintLabel.frame = NSRect(x: hintX, y: textY,
                                 width: max(0, hintRight - hintX), height: Metrics.footerTextHeight)
    }

    // MARK: 动作（子视图构建与菜单分发见 ClipboardPanelView+Subviews.swift）

    @objc func filterChanged() {
        guard let filter = ClipboardFilter(rawValue: filterControl.selectedSegment) else { return }
        self.filter = filter
        delegate?.panelView(self, didSelectFilter: filter)
    }

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