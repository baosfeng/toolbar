import AppKit
import NetworkMonitorCore

// MARK: - Token 页行视图（分布行 / 对比行 / 键值行 / 图例 / 状态带）

/// 分布行：名称（尾部可省略）+「数值 · 占比」右对齐成一列
///
/// r3 改版：去掉左侧序号列（省 12–16pt 给名称）。半宽卡（主面板项目 / 模型）排两行——
/// 名称独占第一行拿满可用宽度，数值与占比右对齐成第二行；整宽列表（二级页）排单行，
/// 数值与占比固定在右侧一列。两种排法的行高都由 TokenPaneStyle 给死，块内统一。
final class TokenDistroRowView: NSView {

    private let nameLabel: NSTextField
    private let valueLabel: NSTextField

    init(height: CGFloat = TokenPaneStyle.distroRowHeight, stacked: Bool = true) {
        nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowNameFont,
                                        color: TokenPaneStyle.secondaryText)
        valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowValueFont,
                                         color: TokenPaneStyle.tertiaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        // 单行强制：名称超长只走尾部省略，不允许回绕成两行（行高由 TokenPaneStyle 给死）
        nameLabel.usesSingleLineMode = true
        valueLabel.usesSingleLineMode = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
        if stacked {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 0
            let detailRow = NSStackView(views: [MenuPanelLabel.spacer(), valueLabel])
            detailRow.orientation = .horizontal
            detailRow.alignment = .centerY
            detailRow.spacing = 0
            stack.addArrangedSubview(nameLabel)
            stack.addArrangedSubview(detailRow)
            nameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            detailRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.addArrangedSubview(nameLabel)
            stack.addArrangedSubview(valueLabel)
            // 数值按自身文字宽度铺开（下限 distroValueWidth），名称拿剩下的宽度并尾部省略。
            // 原因：固定 44pt 时「3.37B · 20.4%」实测需要 75pt，每行数值都被截到「3.37B…」，
            // 而名称只用到 143pt、行内还空着 87pt。数值不截断、名称在空间不足时才截断。
            valueLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: TokenPaneStyle.distroValueWidth).isActive = true
        }
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// - Parameter showsProvider: 半宽卡放不下 "provider/model"，主面板传 false（provider 在二级页与无障碍文案里保留）
    func update(row: TokenDistroRow, showsProvider: Bool = true) {
        let provider = (showsProvider && !row.provider.isEmpty) ? row.provider + "/" : ""
        nameLabel.stringValue = provider + row.name
        valueLabel.stringValue = row.amount + " · " + TokenFormatting.percent(row.share)
        setAccessibilityLabel("\(row.rank) " + provider + row.name + " " + row.amount
            + " " + TokenFormatting.percent(row.share))
    }

#if DEBUG
    /// 快照自证：名称 / 数值标签的实到宽度与「完整显示所需宽度」（needed > available 即截断）
    ///
    /// 另给行宽 / 行高 / 名称实到高度：名称高过行高即「压行」，行宽用于复算可用宽度。
    func metricsForSnapshot(in reference: NSView)
        -> (available: CGFloat, needed: CGFloat, text: String, value: String,
            rowWidth: CGFloat, rowHeight: CGFloat, nameHeight: CGFloat,
            valueAvailable: CGFloat, valueNeeded: CGFloat) {
        layoutSubtreeIfNeeded()
        // 用「文字区宽度 vs 纯文本宽度」判定截断：NSTextField 的 cell 内边距会把
        // intrinsicContentSize 撑大 4pt，拿 frame 宽度直接比会漏判「刚好差 2pt」的省略。
        let nameFrame = nameLabel.convert(nameLabel.bounds, to: reference)
        return (Self.textArea(nameLabel),
                Self.textWidth(nameLabel.stringValue, font: nameLabel.font),
                nameLabel.stringValue,
                valueLabel.stringValue,
                bounds.width,
                bounds.height,
                nameFrame.height,
                Self.textArea(valueLabel),
                Self.textWidth(valueLabel.stringValue, font: valueLabel.font))
    }

    /// 标签的可绘制文字宽度（去掉 cell 内边距）
    private static func textArea(_ label: NSTextField) -> CGFloat {
        label.cell?.drawingRect(forBounds: label.bounds).width ?? label.bounds.width
    }

    /// 完整显示所需文字宽度（按当前字体量纯文本）
    private static func textWidth(_ text: String, font: NSFont?) -> CGFloat {
        let size = (text as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 10.5)])
        return (size.width * 100).rounded(.up) / 100
    }
#endif
}

/// 今日 vs 昨日对比行：名称 + 两条横条 + 数值
final class TokenCompareRowView: NSView {

    private let nameLabel: NSTextField
    private let valueLabel: NSTextField
    private let barView = TokenStackBarView(height: 6)
    private var fraction: Double = 0
    private var color: NSColor = TokenPaneStyle.ghostColor

    init() {
        nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowPercentFont,
                                        color: TokenPaneStyle.tertiaryText)
        valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowValueFont,
                                         color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [nameLabel, barView, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 14),
            nameLabel.widthAnchor.constraint(equalToConstant: 46),
            valueLabel.widthAnchor.constraint(equalToConstant: 54),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(name: String, text: String, fraction: Double, color: NSColor) {
        nameLabel.stringValue = name
        valueLabel.stringValue = text
        self.fraction = fraction
        self.color = color
        barView.update(shares: [fraction], colors: [color], accessibility: name + " " + text)
        setAccessibilityLabel(name + " " + text)
    }
}

/// 二级页键值行（左标签 + 右数值，可着色）
final class TokenKeyRowView: NSView {

    private let titleLabel: NSTextField
    private let valueLabel: NSTextField

    init() {
        titleLabel = MenuPanelLabel.text("", font: TokenPaneStyle.keyRowTitleFont,
                                         color: TokenPaneStyle.tertiaryText)
        valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.keyRowValueFont,
                                         color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(title: String, value: String, color: NSColor = TokenPaneStyle.secondaryText) {
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        valueLabel.textColor = color
        setAccessibilityLabel(title + " " + value)
    }
}

/// 图例行：色块 + 标题 + 数值
final class TokenLegendRowView: NSView {

    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 13),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// items 为（色、标题、数值）；色为 nil 时画虚线色块（累计基准）
    func update(items: [(color: NSColor?, title: String, value: String)]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in items {
            let swatch = TokenSwatch(color: item.color)
            stack.addArrangedSubview(swatch)
            stack.addArrangedSubview(MenuPanelLabel.text(item.title,
                                                         font: TokenPaneStyle.legendFont,
                                                         color: TokenPaneStyle.tertiaryText))
            if !item.value.isEmpty {
                stack.addArrangedSubview(MenuPanelLabel.text(item.value,
                                                             font: TokenPaneStyle.legendValueFont,
                                                             color: TokenPaneStyle.secondaryText))
            }
        }
        setAccessibilityLabel(items.map { $0.title + " " + $0.value }.joined(separator: "，"))
    }
}

/// 图例小色块（虚线态画成一条短划线）
final class TokenSwatch: NSView {

    private let color: NSColor?

    init(color: NSColor?) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: color == nil ? 9 : 6),
            heightAnchor.constraint(equalToConstant: color == nil ? 1 : 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let color else {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
            path.lineWidth = 1.4
            path.setLineDash([2.4, 2], count: 2, phase: 0)
            TokenPaneStyle.secondaryText.withAlphaComponent(0.55).setStroke()
            path.stroke()
            return
        }
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// 坐标轴行（等宽分列，8 / 24 个刻度都能对齐）
final class TokenAxisView: NSView {

    private let stack = NSStackView()
    private var labels: [String] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 10),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(labels: [String]) {
        guard labels != self.labels else { return }
        self.labels = labels
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for label in labels {
            let field = MenuPanelLabel.text(label, font: TokenPaneStyle.axisFont,
                                            color: TokenPaneStyle.tertiaryText)
            field.alignment = .center
            field.lineBreakMode = .byClipping
            stack.addArrangedSubview(field)
        }
    }
}
