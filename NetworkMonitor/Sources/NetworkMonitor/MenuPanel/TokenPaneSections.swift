import AppKit
import NetworkMonitorCore

// MARK: - hero 卡片

/// 今日合计卡片 —— 大数字 + 三项占位 + 环比徽标
final class TokenHeroView: NSView {

    private let heroLabel = MenuPanelLabel.text("", font: TokenPaneStyle.heroUnitFont,
                                                color: TokenPaneStyle.secondaryText)
    private let windowLabel = MenuPanelLabel.text("", font: TokenPaneStyle.axisFont,
                                                  color: TokenPaneStyle.tertiaryText)
    private let valueLabel = MenuPanelLabel.text("0", font: TokenPaneStyle.heroFont)
    private let unitLabel = MenuPanelLabel.text("token · 三项合计", font: TokenPaneStyle.heroUnitFont,
                                                color: TokenPaneStyle.secondaryText)
    /// 第一行：输入 / 输出 / 缓存 三个胶囊
    private let metricRow = NSStackView()
    /// 第二行：请求胶囊 + 「对比昨日 00–17 时」说明文字（文字不是胶囊，对齐原型）
    private let noteRow = NSStackView()
    private let noteLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                                color: TokenPaneStyle.tertiaryText)
    private let cardStack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        windowLabel.alignment = .right

        let headRow = NSStackView(views: [heroLabel, MenuPanelLabel.spacer(), windowLabel])
        headRow.orientation = .horizontal
        headRow.alignment = .firstBaseline
        headRow.spacing = 5

        let valueRow = NSStackView(views: [valueLabel, unitLabel, MenuPanelLabel.spacer()])
        valueRow.orientation = .horizontal
        valueRow.alignment = .firstBaseline
        valueRow.spacing = 5

        metricRow.orientation = .horizontal
        metricRow.alignment = .firstBaseline
        metricRow.spacing = 4
        // 说明文字与请求胶囊同一行：用 centerY 对齐，避免 firstBaseline 把文字抬到胶囊上方
        noteRow.orientation = .horizontal
        noteRow.alignment = .centerY
        noteRow.spacing = 5

        cardStack.orientation = .vertical
        cardStack.alignment = .width
        cardStack.spacing = 5
        cardStack.addArrangedSubview(headRow)
        cardStack.addArrangedSubview(valueRow)
        cardStack.addArrangedSubview(metricRow)
        cardStack.addArrangedSubview(noteRow)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            cardStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cardStack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            cardStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        // 两行徽标显式撑满卡片内容宽度（行内按内容宽排布，右侧留白与原型一致）
        for view in [metricRow, noteRow] as [NSView] {
            view.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.cardFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }

    /// 应用展示模型
    func update(_ model: TokenPaneModel) {
        heroLabel.stringValue = model.heroLabel
        windowLabel.stringValue = model.windowLabel
        valueLabel.stringValue = model.heroValue

        // 原型布局：第一行 输入 / 输出 / 缓存 三个胶囊（内容宽，自动换行在原生里由固定两行替代）；
        // 第二行 请求胶囊 + 「对比昨日 00–17 时」说明文字，同一行左对齐
        for row in [metricRow, noteRow] {
            for view in row.arrangedSubviews {
                row.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        let valueBadges = Array(model.badges.filter { $0.value != nil }.prefix(4))
        for badge in valueBadges.prefix(3) {
            metricRow.addArrangedSubview(TokenBadgeView(title: badge.title,
                                                        value: badge.value,
                                                        isUp: badge.isUp))
        }
        for badge in valueBadges.dropFirst(3) {
            noteRow.addArrangedSubview(TokenBadgeView(title: badge.title,
                                                      value: badge.value,
                                                      isUp: badge.isUp))
        }
        noteLabel.stringValue = model.compareNote ?? ""
        noteLabel.isHidden = (model.compareNote ?? "").isEmpty
        if !noteLabel.isHidden { noteRow.addArrangedSubview(noteLabel) }
        metricRow.isHidden = valueBadges.isEmpty
        noteRow.isHidden = noteRow.arrangedSubviews.isEmpty
    }
}

// MARK: - 环比徽标

/// 小胶囊：`输入 ↑ 41.4×`；`value == nil` 时只显示说明文字
final class TokenBadgeView: NSView {

    private let contentStack = NSStackView()

    init(title: String, value: String?, isUp: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 胶囊按内容宽度排布（原型同为内容宽），只保证文字不被压缩
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.orientation = .horizontal
        contentStack.alignment = .firstBaseline
        contentStack.spacing = 3
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 1.5),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1.5),
        ])
        let titleLabel = MenuPanelLabel.text(title, font: TokenPaneStyle.badgeTitleFont,
                                             color: TokenPaneStyle.secondaryText)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(titleLabel)
        if let value {
            let valueLabel = MenuPanelLabel.text(value, font: TokenPaneStyle.badgeValueFont,
                                                 color: isUp ? TokenPaneStyle.cacheColor : TokenPaneStyle.tertiaryText)
            valueLabel.setContentHuggingPriority(.required, for: .horizontal)
            contentStack.addArrangedSubview(valueLabel)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        TokenPaneStyle.translucent(0.035).setFill()
        path.fill()
        TokenPaneStyle.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - 三项分卡

/// 未缓存输入 / 输出 / 缓存读 三列分卡（等宽，1pt 间隙露出底色）
final class TokenChipRowView: NSView {

    private let row = NSStackView()
    private let chips = (0..<3).map { _ in TokenChipView() }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 1
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        for chip in chips { row.addArrangedSubview(chip) }
        // 原型 hour-chips 锚点高 60px：显式对齐
        heightAnchor.constraint(equalToConstant: 60).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.hairline.setFill()
        bounds.fill()
    }

    /// 应用三项数值与占比
    func update(_ items: [TokenPaneModel.Chip]) {
        for (chip, item) in zip(chips, items) { chip.update(item) }
    }
}

/// 单项分卡
final class TokenChipView: NSView {

    private let titleLabel = MenuPanelLabel.text("", font: TokenPaneStyle.chipTitleFont,
                                                 color: TokenPaneStyle.secondaryText)
    private let valueLabel = MenuPanelLabel.text("0", font: TokenPaneStyle.chipValueFont)
    private let shareLabel = MenuPanelLabel.text("", font: TokenPaneStyle.chipShareFont,
                                                 color: TokenPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for label in [titleLabel, valueLabel, shareLabel] {
            label.lineBreakMode = .byClipping
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let stack = NSStackView(views: [titleLabel, valueLabel, shareLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -5),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.translucent(0.03).setFill()
        bounds.fill()
    }

    /// 更新单卡
    func update(_ chip: TokenPaneModel.Chip) {
        titleLabel.stringValue = chip.title
        valueLabel.stringValue = chip.value
        shareLabel.stringValue = chip.share
    }
}