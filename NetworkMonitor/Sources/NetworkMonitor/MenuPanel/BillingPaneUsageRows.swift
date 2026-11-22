import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - 图表坐标轴

/// 图表首尾坐标轴 — 左首桶时间、右「现在 / 今天」
final class BillingAxisRow: NSView {

    private let leftLabel = MenuPanelLabel.text("", font: BillingPaneStyle.axisFont,
                                                color: BillingPaneStyle.tertiaryText)
    private let rightLabel = MenuPanelLabel.text("", font: BillingPaneStyle.axisFont,
                                                 color: BillingPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rightLabel.alignment = .right
        let stack = NSStackView(views: [leftLabel, MenuPanelLabel.spacer(), rightLabel])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(left: String, right: String) {
        leftLabel.stringValue = left
        rightLabel.stringValue = right
    }
}
