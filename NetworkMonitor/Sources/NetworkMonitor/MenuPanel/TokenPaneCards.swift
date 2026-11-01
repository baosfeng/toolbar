import AppKit
import NetworkMonitorCore

// MARK: - Token 页卡片与图表基础件

/// 可点击卡片：圆角底 + 竖向内容栈（整卡可点，键盘焦点由面板根视图驱动）
///
/// 卡片一律是 MenuPanelRow 子类：悬停高亮 / 键盘焦点环 / Enter-空格触发三件
/// 都由基类提供，二级页入口和主面板区块共用同一套交互。
class TokenCardRow: MenuPanelRow {

    /// 内容容器（自上而下排列）
    let body = NSStackView()

    private let background: NSColor
    private let radius: CGFloat

    init(height: CGFloat,
         background: NSColor,
         radius: CGFloat = TokenPaneStyle.cardRadius,
         paddingX: CGFloat = TokenPaneStyle.cardPaddingX,
         paddingY: CGFloat = TokenPaneStyle.cardPaddingY,
         spacing: CGFloat = 2,
         onClick: (() -> Void)? = nil) {
        self.background = background
        self.radius = radius
        super.init(height: height, onClick: onClick)
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = spacing
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
            body.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        super.draw(dirtyRect)
    }
}

/// 卡头：标题 + 弹簧 + 说明 + 可选右侧控件
final class TokenCardHead: NSView {

    private let titleLabel: NSTextField
    private let metaLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                                color: TokenPaneStyle.tertiaryText)

    init(title: String, titleFont: NSFont = TokenPaneStyle.cardHeadTitleFont, trailing: NSView? = nil) {
        titleLabel = MenuPanelLabel.text(title, font: titleFont, color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, metaLabel, MenuPanelLabel.spacer()])
        if let trailing { stack.addArrangedSubview(trailing) }
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 13),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(title: String? = nil, meta: String) {
        if let title { titleLabel.stringValue = title }
        metaLabel.stringValue = meta
    }
}


/// 自适应高度卡片（二级页用）：底 + 内边距 + 竖向内容，高度由内容决定
final class TokenBoxView: NSView {

    let body = NSStackView()

    private let background: NSColor
    private let radius: CGFloat
    private let paddingX: CGFloat
    private let paddingY: CGFloat

    init(background: NSColor = TokenPaneStyle.cardFill,
         radius: CGFloat = 9,
         paddingX: CGFloat = 9,
         paddingY: CGFloat = 7,
         spacing: CGFloat = 5) {
        self.background = background
        self.radius = radius
        self.paddingX = paddingX
        self.paddingY = paddingY
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = spacing
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
            body.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -paddingY),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        super.draw(dirtyRect)
    }

    /// 清空并重新装配行（二级页每次进入重建，避免残留旧数据）
    func setRows(_ rows: [NSView]) {
        for view in body.arrangedSubviews {
            body.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in rows { body.addArrangedSubview(row) }
        for row in rows where !(row is NSTextField) {
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }
}

/// 分族卡（2×2 首屏矩阵的一格）：标题行（含走势条）+ 大数值 + 一行辅助
///
/// r3 改版：走势条收进标题行右侧（不再单独占一行），同比与占比合并成一行辅助，
/// 卡片从「大数字 + 两行辅助」压成「大数字 + 一行辅助」，省下的高度全部给字号。
final class TokenFamilyCardView: TokenCardRow {

    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let unitLabel: NSTextField
    private let auxLabel: NSTextField
    private let spark = TokenSparkView(height: TokenPaneStyle.sparkHeight)
    private let miniBars = TokenMiniBarsView(height: TokenPaneStyle.sparkHeight)
    private var metricIndex = 0

    init(metric: TokenMetric, onClick: @escaping () -> Void) {
        titleLabel = MenuPanelLabel.text(metric.title, font: TokenPaneStyle.cardTitleFont,
                                         color: TokenPaneStyle.secondaryText)
        valueLabel = MenuPanelLabel.text("—", font: TokenPaneStyle.cardValueFont,
                                         color: TokenPaneStyle.secondaryText)
        unitLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaValueFont,
                                        color: TokenPaneStyle.tertiaryText)
        auxLabel = MenuPanelLabel.text("—", font: TokenPaneStyle.cardFooterFont,
                                       color: TokenPaneStyle.tertiaryText)
        metricIndex = metric.rawValue
        super.init(height: TokenPaneStyle.familyCardHeight,
                   background: TokenPaneStyle.metricCardFill(metric.rawValue),
                   spacing: 2,
                   onClick: onClick)

        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        auxLabel.lineBreakMode = .byTruncatingTail
        auxLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 走势条与标题同行：右端固定宽度，省掉卡片里的一整行
        let headRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), spark, miniBars])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        for chart in [spark as NSView, miniBars as NSView] {
            chart.widthAnchor.constraint(equalToConstant: TokenPaneStyle.cardSparkWidth).isActive = true
        }
        miniBars.isHidden = true

        let valueRow = NSStackView(views: [valueLabel, unitLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .lastBaseline
        valueRow.spacing = 2
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)

        for row in [headRow, valueRow, auxLabel] {
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        setAccessibilityRole(.button)
        setAccessibilityLabel(metric.title + "详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(card: TokenFamilyCard) {
        titleLabel.stringValue = card.title
        valueLabel.stringValue = card.value
        valueLabel.textColor = TokenPaneStyle.metricInk(metricIndex)
        unitLabel.stringValue = card.unit
        auxLabel.stringValue = card.aux
        auxLabel.textColor = card.hasDelta
            ? (card.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk)
            : TokenPaneStyle.tertiaryText

        let isBars = card.metric == .request
        spark.isHidden = isBars
        miniBars.isHidden = !isBars
        let accessibility = card.title + " " + card.value + " " + card.unit + " " + card.aux
        if isBars {
            miniBars.update(values: card.series, accessibility: accessibility)
        } else {
            spark.update(values: card.series, accessibility: accessibility)
        }
        setAccessibilityLabel(card.title + "详情，" + card.value + " " + card.unit)
        setAccessibilityValue(accessibility)
    }
}

/// 行内文字按钮（「切：请求数」「切：分线」）
final class TokenTextButton: NSButton {

    var onClick: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.title = title
        font = TokenPaneStyle.textButtonFont
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = TokenPaneStyle.uncachedInk
        setButtonType(.momentaryChange)
        target = self
        action = #selector(handleClick)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func handleClick() { onClick?() }

    func update(title: String) {
        self.title = title
        setAccessibilityLabel(title)
    }
}