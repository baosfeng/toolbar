import AppKit
import NetworkMonitorCore

// MARK: - 模型分布列表

/// 环形图右侧的模型清单：色点 + 模型名 + provider·占比 + 数值
final class TokenModelListView: NSView {

    private let stack = NSStackView()
    private var rows: [TokenModelRowView] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 纯容器：背景由页面绘制
    }

    /// 更新清单（Top 5 + 其它）
    func update(_ rows: [TokenPaneModel.ModelRow]) {
        while self.rows.count > rows.count, let last = self.rows.popLast() {
            stack.removeArrangedSubview(last)
            last.removeFromSuperview()
        }
        while self.rows.count < rows.count {
            let row = TokenModelRowView()
            stack.addArrangedSubview(row)
            self.rows.append(row)
        }
        for (row, item) in zip(self.rows, rows) { row.update(item) }
    }
}

/// 单条模型行
final class TokenModelRowView: NSView {

    private let dot = TokenDotView()
    private let nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.listNameFont,
                                                color: TokenPaneStyle.secondaryText)
    private let subLabel = MenuPanelLabel.text("", font: TokenPaneStyle.listSubFont,
                                               color: TokenPaneStyle.tertiaryText)
    private let amountLabel = MenuPanelLabel.text("", font: TokenPaneStyle.listValueFont,
                                                  color: TokenPaneStyle.secondaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
        nameLabel.lineBreakMode = .byTruncatingTail
        subLabel.lineBreakMode = .byTruncatingTail
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [nameLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [dot, textStack, MenuPanelLabel.spacer(), amountLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新单条
    func update(_ row: TokenPaneModel.ModelRow) {
        dot.color = TokenPaneStyle.modelColor(row.colorIndex)
        nameLabel.stringValue = row.name
        subLabel.stringValue = row.sub
        amountLabel.stringValue = row.amount
    }
}

// MARK: - 项目分布列表

/// 项目横条清单：项目名 + 会话数/占比 + 数值 + 占比条
final class TokenProjectListView: NSView {

    private let stack = NSStackView()
    private var rows: [TokenProjectRowView] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 纯容器
    }

    /// 更新清单（Top 5）
    func update(_ rows: [TokenPaneModel.ProjectRow]) {
        while self.rows.count > rows.count, let last = self.rows.popLast() {
            stack.removeArrangedSubview(last)
            last.removeFromSuperview()
        }
        while self.rows.count < rows.count {
            let row = TokenProjectRowView()
            stack.addArrangedSubview(row)
            self.rows.append(row)
        }
        for (row, item) in zip(self.rows, rows) { row.update(item) }
    }
}

/// 单条项目行：标题行 + 4pt 占比条
final class TokenProjectRowView: NSView {

    private let nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.listNameFont)
    private let subLabel = MenuPanelLabel.text("", font: TokenPaneStyle.listSubFont,
                                               color: TokenPaneStyle.tertiaryText)
    private let amountLabel = MenuPanelLabel.text("", font: TokenPaneStyle.listValueFont)
    private let bar = TokenBarView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        subLabel.setContentHuggingPriority(.required, for: .horizontal)
        subLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topRow = NSStackView(views: [nameLabel, subLabel, MenuPanelLabel.spacer(), amountLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 6

        let stack = NSStackView(views: [topRow, bar])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新单条
    func update(_ row: TokenPaneModel.ProjectRow) {
        nameLabel.stringValue = row.name
        subLabel.stringValue = row.sub
        amountLabel.stringValue = row.amount
        bar.update(fraction: row.share)
    }
}

// MARK: - 迷你图卡片

/// 迷你卡：标题 + 数值 + 右侧标签 + 30pt 图形
final class TokenMiniCardView: NSView {

    private let titleLabel: NSTextField
    private let valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.miniValueFont)
    private let tagLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                              color: TokenPaneStyle.tertiaryText)
    let chart: NSView

    init(title: String, chart: NSView) {
        titleLabel = MenuPanelLabel.text(title, font: TokenPaneStyle.miniTitleFont,
                                         color: TokenPaneStyle.secondaryText)
        self.chart = chart
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        chart.translatesAutoresizingMaskIntoConstraints = false
        let head = NSStackView(views: [titleLabel, valueLabel, MenuPanelLabel.spacer(), tagLabel])
        head.orientation = .horizontal
        head.alignment = .firstBaseline
        head.spacing = 5
        let stack = NSStackView(views: [head, chart])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            chart.heightAnchor.constraint(equalToConstant: TokenPaneStyle.miniChartHeight),
            // 原型 reuse-spark / requests-spark 锚点高 64px：显式对齐
            heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        TokenPaneStyle.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// 更新数值与右侧标签
    func update(value: String, tag: String) {
        valueLabel.stringValue = value
        tagLabel.stringValue = tag
    }
}

// MARK: - 小构件

/// 小色点（模型图例）
final class TokenDotView: NSView {

    var color: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
    }
}

/// 4pt 占比条
final class TokenBarView: NSView {

    private var fraction: Double = 0

    /// 更新填充比例（0…1）
    func update(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = max(bounds.height / 2, 1)
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard fraction > 0 else { return }
        let width = max(bounds.height, bounds.width * CGFloat(fraction))
        TokenPaneStyle.cacheColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}