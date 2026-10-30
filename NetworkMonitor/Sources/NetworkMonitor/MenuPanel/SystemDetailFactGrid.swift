import AppKit

// MARK: - 详情页「标签 / 数值」两列网格

/// 详情页事实网格 — 每行「标签 + 数值 + 单位」，两列并排（原型 `.dgrid`）
///
/// 数值用等宽数字（11pt semibold），单位 8.5pt 弱文字；`isKey` 行按所在族的 ink 上色
/// （GPU 详情「已用显存」、内存「交换」、磁盘「已用」）。不可得值保持「—」并转弱文字色，
/// 不留空行 —— 降级态与真实读数一眼可分。
final class SystemDetailFactGrid: NSView {

    /// 单条事实
    struct Item {
        let label: String
        let value: String
        let unit: String?
        let isKey: Bool
    }

    private struct Line {
        let pairs: [NSStackView]
        let valueViews: [SystemMetricValueView]
    }

    private var lines: [Line] = []
    private let rowCount: Int
    private let columnCount: Int

    init(rows: Int, columns: Int = 2) {
        rowCount = max(1, rows)
        columnCount = max(1, min(columns, 2))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let lineCount = Int((Double(rowCount) / Double(columnCount)).rounded(.up))
        for _ in 0..<lineCount {
            var pairViews: [NSStackView] = []
            var valueViews: [SystemMetricValueView] = []
            for _ in 0..<columnCount {
                let value = SystemMetricValueView(fontSize: 11, unitFontSize: 8.5, weight: .semibold)
                let pair = NSStackView(views: [MenuPanelLabel.text("", font: Self.labelFont,
                                                                  color: SystemPalette.meta),
                                               MenuPanelLabel.spacer(), value])
                pair.orientation = .horizontal
                pair.alignment = .firstBaseline
                pair.spacing = 4
                pairViews.append(pair)
                valueViews.append(value)
            }
            let line = NSStackView(views: pairViews)
            line.orientation = .horizontal
            line.alignment = .firstBaseline
            line.spacing = 10
            line.distribution = .fillEqually
            outer.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
            lines.append(Line(pairs: pairViews, valueViews: valueViews))
        }
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)

    /// 更新事实行（不足 rowCount 时多出来的行留「—」；超出部分忽略）
    func update(_ items: [Item], keyColor: NSColor) {
        for (index, line) in lines.enumerated() {
            for column in 0..<columnCount {
                let itemIndex = index * columnCount + column
                let pair = line.pairs[column]
                let label = pair.arrangedSubviews.first as? NSTextField
                let valueView = line.valueViews[column]
                guard itemIndex < items.count else {
                    label?.stringValue = ""
                    valueView.update(value: SystemPaneFormat.placeholder, color: SystemPalette.meta)
                    continue
                }
                let item = items[itemIndex]
                label?.stringValue = item.label
                let available = item.value != SystemPaneFormat.placeholder
                let color = available ? (item.isKey ? keyColor : SystemPalette.foreground)
                    : SystemPalette.meta
                valueView.update(value: item.value, color: color, unit: item.unit)
            }
        }
        invalidateIntrinsicContentSize()
    }
}
