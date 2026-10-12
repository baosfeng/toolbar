import AppKit
import NetworkMonitorCore

// MARK: - 过滤类型

/// 面板过滤（Tab 循环切换：全部 → 文本 → 图片 → 收藏）
enum ClipboardFilter: Int, CaseIterable {
    case all
    case text
    case image
    case pinned

    /// 中文名称（无障碍描述与提示文案）
    var label: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .pinned: return "收藏"
        }
    }

    /// SF Symbol（禁止 emoji）
    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .pinned: return "star.fill"
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

/// 剪贴板面板内容视图 — 搜索框、过滤切换、卡片流、栈进度与权限状态
///
/// 布局：顶部搜索 + 过滤 + 采集按钮，中部卡片流（含空态），底部栈进度 / 提示 / 权限入口。
@MainActor
final class ClipboardPanelView: NSView, NSSearchFieldDelegate {

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

    /// 更新栈进度（如「栈 2 / 5」）
    func updateStack(remaining: Int, total: Int) {
        let suffix = remaining > 0 ? "\(remaining) / \(total)" : "空"
        stackLabel.stringValue = "栈 \(suffix)"
    }

    /// 更新辅助功能权限状态（无权限时显示入口，不得静默）
    func updatePermission(accessibilityGranted: Bool) {
        accessibilityButton.isHidden = accessibilityGranted
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
        let padding: CGFloat = 10
        let headerHeight: CGFloat = 24

        let searchWidth = min(max(180, width * 0.38), 360)
        searchField.frame = NSRect(x: padding, y: padding, width: searchWidth, height: headerHeight)
        filterControl.frame = NSRect(x: padding + searchWidth + 10, y: padding, width: 136, height: headerHeight)
        let buttonX = padding + searchWidth + 156
        captureButton.frame = NSRect(x: buttonX, y: padding, width: max(120, width - buttonX - padding), height: headerHeight)

        let footerY = height - 28
        stackLabel.frame = NSRect(x: padding, y: footerY, width: 110, height: 18)
        let permissionWidth: CGFloat = accessibilityButton.isHidden ? 0 : 132
        if !accessibilityButton.isHidden {
            accessibilityButton.frame = NSRect(x: width - padding - permissionWidth, y: footerY - 3,
                                               width: permissionWidth, height: 22)
        }
        let hintX = padding + 116
        hintLabel.frame = NSRect(x: hintX, y: footerY,
                                 width: max(0, width - hintX - padding - permissionWidth - 8), height: 18)

        // scrollTop 与 footerY 取值保证默认面板高度 260 下可完整容纳 190 高卡片
        let scrollTop = padding + headerHeight + 4
        cardFlow.frame = NSRect(x: padding - 6, y: scrollTop,
                                width: width - (padding - 6) * 2,
                                height: max(0, footerY - scrollTop - 4))
    }

    // MARK: 子视图构建

    private func buildSearchField() {
        searchField.placeholderString = "搜索剪贴板历史"
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
        for filter in ClipboardFilter.allCases {
            filterControl.setImage(symbolImage(named: filter.symbolName), forSegment: filter.rawValue)
            filterControl.setWidth(32, forSegment: filter.rawValue)
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
        captureButton.image = symbolImage(named: "arrow.clockwise")
        captureButton.imagePosition = .imageLeading
        captureButton.target = self
        captureButton.action = #selector(captureNow)
        addSubview(captureButton)
    }

    private func buildFooter() {
        stackLabel.font = NSFont.systemFont(ofSize: 11)
        stackLabel.textColor = .secondaryLabelColor
        addSubview(stackLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        addSubview(hintLabel)

        accessibilityButton.title = "前往系统设置"
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.controlSize = .mini
        accessibilityButton.font = NSFont.systemFont(ofSize: 11)
        accessibilityButton.contentTintColor = .systemOrange
        accessibilityButton.image = symbolImage(named: "exclamationmark.triangle")
        accessibilityButton.imagePosition = .imageLeading
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibilitySettings)
        addSubview(accessibilityButton)
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
        addSubview(cardFlow)
    }

    private func symbolImage(named name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
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
