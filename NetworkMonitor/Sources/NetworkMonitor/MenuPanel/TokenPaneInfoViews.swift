import AppKit
import NetworkMonitorCore

// MARK: - 图例

/// 图例项（color 为 nil 时画斜纹）
struct TokenLegendItem {
    let title: String
    let color: NSColor?
}

/// 色块图例（缓存读 / 输出 / 未缓存输入 / 斜纹说明）
final class TokenLegendView: NSView {

    private let stack = NSStackView()

    init(items: [TokenLegendItem]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for item in items {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 3
            let swatch = TokenSwatchView()
            swatch.color = item.color
            swatch.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 6),
                swatch.heightAnchor.constraint(equalToConstant: 6),
            ])
            row.addArrangedSubview(swatch)
            row.addArrangedSubview(MenuPanelLabel.text(item.title, font: TokenPaneStyle.legendFont,
                                                       color: TokenPaneStyle.tertiaryText))
            stack.addArrangedSubview(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// 图例色块（color 为 nil 时画斜纹小方块）
final class TokenSwatchView: NSView {

    var color: NSColor? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        if let color {
            color.setFill()
            path.fill()
        } else {
            TokenChartSupport.drawHatch(in: bounds, color: TokenPaneStyle.trackColor, spacing: 2)
        }
    }
}

// MARK: - 分区标题

/// 分区标题行：左侧标题 + 右侧说明 + 可选右侧控件
final class TokenSectionHeaderView: NSView {

    private let titleLabel: NSTextField
    private let metaLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                                color: TokenPaneStyle.tertiaryText)
    private let stack = NSStackView()

    init(title: String, trailing: NSView? = nil) {
        titleLabel = MenuPanelLabel.text(title, font: TokenPaneStyle.sectionTitleFont,
                                         color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(MenuPanelLabel.spacer())
        stack.addArrangedSubview(metaLabel)
        if let trailing { stack.addArrangedSubview(trailing) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新右侧说明文案
    func updateMeta(_ text: String) {
        metaLabel.stringValue = text
    }
}

// MARK: - 本周 / 累计摘要

/// 两行摘要卡：本周 / 累计的输入、输出、缓存
final class TokenSummaryView: NSView {

    private let weekLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [weekLabel, totalLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -9),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        // 原型 compare-week-total 锚点高 46px：显式对齐
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        for label in [weekLabel, totalLabel] {
            label.lineBreakMode = .byClipping
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        TokenPaneStyle.translucent(0.03).setFill()
        path.fill()
        TokenPaneStyle.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// 应用两行数据（parts 顺序：未缓存输入 / 输出 / 缓存读）
    func update(week: [String], total: [String]) {
        weekLabel.attributedStringValue = Self.line(tag: "本周", parts: week)
        totalLabel.attributedStringValue = Self.line(tag: "累计", parts: total)
    }

    /// 构造一行富文本：标签加粗 + 等宽数值
    private static func line(tag: String, parts: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let tagAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: TokenPaneStyle.secondaryText,
        ]
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: TokenPaneStyle.tertiaryText,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: TokenPaneStyle.secondaryText,
        ]
        result.append(NSAttributedString(string: tag + "  ", attributes: tagAttributes))
        let units = ["输入", "输出", "缓存"]
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: " · ", attributes: unitAttributes)) }
            result.append(NSAttributedString(string: part, attributes: valueAttributes))
            result.append(NSAttributedString(string: " " + units[min(index, units.count - 1)],
                                             attributes: unitAttributes))
        }
        return result
    }
}

// MARK: - 页脚

/// 页脚说明（有数据日跨度 / 会话数 / 口径）
final class TokenFooterView: NSView {

    private let firstLabel = NSTextField(labelWithString: "")
    private let secondLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for label in [firstLabel, secondLabel] {
            label.font = TokenPaneStyle.footerFont
            label.textColor = TokenPaneStyle.tertiaryText
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let stack = NSStackView(views: [firstLabel, secondLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.hairline.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    /// 更新页脚两行
    func update(lines: [String]) {
        firstLabel.stringValue = lines.first ?? ""
        secondLabel.stringValue = lines.count > 1 ? lines[1] : ""
        secondLabel.isHidden = lines.count <= 1
    }
}