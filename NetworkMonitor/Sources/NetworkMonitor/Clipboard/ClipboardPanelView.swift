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
        static let gap: CGFloat = 8
        static let footerTextHeight: CGFloat = 16
    }

    /// 底部常驻按键提示（设计稿固定文案）
    static let keyHint = "↑↓ 选择 / ⌘ 粘贴 / ⌘1–9 直选 / Esc 收起"

    weak var delegate: ClipboardPanelViewDelegate?

    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl()
    private let captureButton = NSButton()
    private let stackLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton()
    /// 卡片流（单行横向滚动 + 视图池 + 滑动窗口，见 ClipboardCardFlowView）
    private let cardFlow = ClipboardCardFlowView()

    /// 当前搜索串
    private(set) var query: String = ""
    /// 当前过滤
    private(set) var filter: ClipboardFilter = .all
    /// 当前选中下标
    private(set) var selectedIndex = -1

    override var isFlipped: Bool { true }

    /// 非激活态首次点击即生效（NSPanel 非激活面板的首次点击必须由视图放行）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildSearchField()
        buildFilterControl()
        buildCaptureButton()
        buildFooter()
        buildCardFlow()
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
        cardFlow.frame = NSRect(x: padding, y: Metrics.toolbarHeight,
                                width: max(0, width - padding * 2), height: cardsHeight)
    }

    /// 工具条：搜索框弹性 300–420、类型过滤、右侧「采集当前剪贴板」
    private func layoutToolbar(width: CGFloat) {
        let padding = Metrics.padding
        let controlY = (Metrics.toolbarHeight - Metrics.controlHeight) / 2
        let captureWidth = max(96, ceil(captureButton.fittingSize.width))
        let searchWidth = min(Metrics.searchMaxWidth,
                              max(Metrics.searchMinWidth,
                                  width - padding * 2 - captureWidth - Metrics.filterWidth - Metrics.gap * 2))
        searchField.frame = NSRect(x: padding, y: controlY,
                                   width: searchWidth, height: Metrics.controlHeight)
        filterControl.frame = NSRect(x: padding + searchWidth + Metrics.gap, y: controlY,
                                     width: Metrics.filterWidth, height: Metrics.controlHeight)
        captureButton.frame = NSRect(x: width - padding - captureWidth, y: controlY,
                                     width: captureWidth, height: Metrics.controlHeight)
    }

    /// 提示行：左侧栈进度、右侧按键提示与「辅助功能权限」入口
    private func layoutFooter(width: CGFloat, height: CGFloat) {
        let padding = Metrics.padding
        let textY = height - Metrics.footerHeight + (Metrics.footerHeight - Metrics.footerTextHeight) / 2
        let permissionWidth = max(72, ceil(accessibilityButton.fittingSize.width))
        let permissionX = width - padding - permissionWidth
        accessibilityButton.frame = NSRect(x: permissionX, y: textY,
                                           width: permissionWidth, height: Metrics.footerTextHeight)

        let stackWidth = stackLabel.isHidden
            ? 0
            : min(120, ceil(stackLabel.intrinsicContentSize.width))
        stackLabel.frame = NSRect(x: padding, y: textY, width: stackWidth, height: Metrics.footerTextHeight)

        let hintX = padding + stackWidth + (stackWidth > 0 ? Metrics.gap : 0)
        let hintRight = permissionX - Metrics.gap
        hintLabel.frame = NSRect(x: hintX, y: textY,
                                 width: max(0, hintRight - hintX), height: Metrics.footerTextHeight)
    }

    /// 工具条上下发丝分隔线（设计稿：工具条底部、提示行顶部各一条）
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: Metrics.toolbarHeight, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: bounds.height - Metrics.footerHeight, width: bounds.width, height: 1).fill()
    }

    // MARK: 子视图构建

    private func buildSearchField() {
        searchField.placeholderString = "搜索剪贴板"
        searchField.delegate = self
        searchField.font = NSFont.systemFont(ofSize: 13)
        // 置空 nextKeyView：Tab 不进入搜索框焦点环（Tab 由面板统一拦截为切换过滤）
        searchField.nextKeyView = nil
        addSubview(searchField)
    }

    private func buildFilterControl() {
        filterControl.segmentCount = ClipboardFilter.allCases.count
        filterControl.segmentStyle = .texturedRounded
        filterControl.trackingMode = .selectOne
        filterControl.font = NSFont.systemFont(ofSize: 12)
        for filter in ClipboardFilter.allCases {
            filterControl.setLabel(filter.label, forSegment: filter.rawValue)
            filterControl.setWidth(40, forSegment: filter.rawValue)
            filterControl.setToolTip(filter.label, forSegment: filter.rawValue)
        }
        filterControl.selectedSegment = ClipboardFilter.all.rawValue
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        addSubview(filterControl)
    }

    private func buildCaptureButton() {
        captureButton.title = "采集当前剪贴板"
        captureButton.bezelStyle = .rounded
        captureButton.controlSize = .small
        captureButton.font = NSFont.systemFont(ofSize: 12)
        captureButton.target = self
        captureButton.action = #selector(captureNow)
        addSubview(captureButton)
    }

    private func buildFooter() {
        stackLabel.font = NSFont.systemFont(ofSize: 11)
        stackLabel.textColor = .secondaryLabelColor
        stackLabel.lineBreakMode = .byTruncatingTail
        stackLabel.isHidden = true
        addSubview(stackLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.alignment = .right
        hintLabel.stringValue = Self.keyHint
        addSubview(hintLabel)

        accessibilityButton.isBordered = false
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        applyPermissionStyle(accessibilityGranted: true)
        addSubview(accessibilityButton)
    }

    /// 权限入口样式：有权限时 10pt muted，无权限时改为 systemOrange 并带警示符号（不得静默）
    private func applyPermissionStyle(accessibilityGranted: Bool) {
        let color: NSColor = accessibilityGranted ? .secondaryLabelColor : .systemOrange
        accessibilityButton.attributedTitle = NSAttributedString(
            string: "辅助功能权限",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: color])
        accessibilityButton.image = accessibilityGranted
            ? nil
            : symbolImage(named: "exclamationmark.triangle", color: .systemOrange)
        accessibilityButton.imagePosition = accessibilityGranted ? .noImage : .imageLeading
    }

    /// 卡片流：点击 / 双击动作全部转交控制器，视图不持有业务依赖
    private func buildCardFlow() {
        cardFlow.onSelect = { [weak self] index in
            guard let self else { return }
            self.delegate?.panelView(self, didSelect: index)
        }
        cardFlow.onActivate = { [weak self] index in
            guard let self else { return }
            self.delegate?.panelView(self, didActivate: index)
        }
        cardFlow.onPin = { [weak self] index in
            guard let self else { return }
            self.delegate?.panelView(self, didRequestPinAt: index)
        }
        addSubview(cardFlow)
    }

    private func symbolImage(named name: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return image.withSymbolConfiguration(configuration) ?? image
    }

    // MARK: 动作

    @objc private func filterChanged() {
        guard let filter = ClipboardFilter(rawValue: filterControl.selectedSegment) else { return }
        self.filter = filter
        delegate?.panelView(self, didSelectFilter: filter)
    }

    @objc private func captureNow() {
        delegate?.panelViewDidRequestCapture(self)
    }

    @objc private func openAccessibilitySettings() {
        delegate?.panelViewDidRequestOpenAccessibilitySettings(self)
    }
}
