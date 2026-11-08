import AppKit

// MARK: - 小型分段控件

/// 分段控件 —— 页面范围（今日 / 近 7 天 / 近 30 天）、小时对比、趋势形态、屏切换条、排行维度共用
///
/// 每段是一个 MenuPanelRow，因此能被面板的键盘焦点遍历命中（Tab / ↑↓ 移动、Enter 触发）。
/// 两种观感：
/// - page：页头 / 范围条，自身 cardFill 底（与页头同色，不抢视觉）；
/// - inline：卡内切换器（排行维度），轨道底色 + 选中实心 pill —— 卡底与卡内控件同色时
///   「看起来像静态标签」是本轮用户反馈的原问题，必须靠轨道与 pill 的明暗差把可点性画出来。
final class TokenSegmentedControl: NSView {

    /// 观感
    enum Style {
        /// 页头 / 范围条：自身底色，选中项用浅色填充
        case page
        /// 卡内切换器：轨道底色 + 选中 pill
        case inline
    }

    /// 选中项变化（参数：下标）
    var onSelect: ((Int) -> Void)?

    private(set) var selectedIndex = 0
    private var rows: [TokenSegmentRow] = []
    private let style: Style

    /// 键盘可达分段
    var focusableRows: [MenuPanelRow] { rows }

    /// - Parameters:
    ///   - expands: true = 撑满可用宽度且各段等宽（屏切换条 / 维度分段）；false = 按文字宽度收紧
    ///   - style: page = 页头观感；inline = 卡内切换器（轨道 + pill）
    init(titles: [String], expands: Bool = false, style: Style = .page) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 1
        if expands { stack.distribution = .fillEqually }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        for (index, title) in titles.enumerated() {
            let row = TokenSegmentRow(title: title, style: style)
            row.onClick = { [weak self] in self?.select(index, notify: true) }
            stack.addArrangedSubview(row)
            rows.append(row)
        }
        select(0, notify: false)
        setContentHuggingPriority(expands ? .defaultLow : .required, for: .horizontal)
        setContentCompressionResistancePriority(expands ? .defaultLow : .required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // inline 用轨道色：与卡底同色时控件会「消失」，看不出是可点的切换器
        let fill = style == .inline ? PaneCardStyle.trackColor : PaneCardStyle.cardFill
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    /// 选中指定分段（notify = false 时不回调，用于外部同步）
    func select(_ index: Int, notify: Bool) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        for (rowIndex, row) in rows.enumerated() {
            row.setSelected(rowIndex == index)
        }
        if notify { onSelect?(index) }
    }
}

/// 单个分段（选中态实心 pill + 半粗文字；段内文字水平居中）
final class TokenSegmentRow: MenuPanelRow {

    private let label: NSTextField
    private var selected = false
    private let style: TokenSegmentedControl.Style

    init(title: String, style: TokenSegmentedControl.Style) {
        self.style = style
        label = MenuPanelLabel.text(title, font: TokenPaneStyle.segmentFont,
                                    color: TokenPaneStyle.secondaryText)
        super.init(height: 16)
        contentStack.spacing = 0
        label.alignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(label)
        // 段内居中：expands 模式下段被拉宽，文字必须跟着段居中（用户反馈「第一个没有居中」）
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    override var isInteractive: Bool { true }

    /// 设置选中态
    func setSelected(_ value: Bool) {
        guard selected != value else { return }
        selected = value
        label.font = value ? TokenPaneStyle.segmentSelectedFont : TokenPaneStyle.segmentFont
        label.textColor = value ? .labelColor : TokenPaneStyle.secondaryText
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            let fill = style == .inline ? PaneCardStyle.cardFill : TokenPaneStyle.selectedFill
            fill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
        } else if isHovered {
            // 悬停也给反馈：让「看起来能点」在鼠标上也成立（鼠标进入已由基类切手型光标）
            let fill = style == .inline ? TokenPaneStyle.trackStrong : TokenPaneStyle.selectedFill
            fill.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}
