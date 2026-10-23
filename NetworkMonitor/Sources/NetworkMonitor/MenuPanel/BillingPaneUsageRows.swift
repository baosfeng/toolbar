import AppKit
import NetworkMonitorCore

// MARK: - 图表坐标轴 / 分隔线

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

/// 1pt 浅分隔线（10% 前景色，深浅色自适应）
final class BillingDividerView: NSView {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        BillingPaneStyle.hairline.setFill()
        bounds.fill()
    }
}

// MARK: - 模型明细行

/// 模型明细行 — 模型名（等宽截断）+ 请求次数 + 金额或 token 合计（右对齐，最小 52pt）
final class BillingModelRow: MenuPanelRow {

    private let nameLabel: NSTextField
    private let requestLabel: NSTextField
    private let amountLabel: NSTextField

    init() {
        nameLabel = MenuPanelLabel.text("", font: BillingPaneStyle.modelNameFont,
                                        color: BillingPaneStyle.secondaryText)
        requestLabel = MenuPanelLabel.text("", font: BillingPaneStyle.modelRequestFont,
                                           color: BillingPaneStyle.tertiaryText)
        amountLabel = MenuPanelLabel.text("", font: BillingPaneStyle.modelAmountFont, color: .labelColor)
        super.init(height: 22, onClick: nil)
        requestLabel.setContentHuggingPriority(.required, for: .horizontal)
        requestLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountLabel.alignment = .right
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(nameLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        contentStack.addArrangedSubview(requestLabel)
        contentStack.addArrangedSubview(amountLabel)
        amountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新一行模型明细
    ///
    /// 右侧数值列按 provider 能力自适应：有金额显示金额；无金额但有 token 明细时
    /// 显示 token 合计（编码计划类 provider 按 credits 计量、不返回花费）；两者都缺才整列隐藏。
    func update(name: String, metrics: BillingMetrics) {
        nameLabel.stringValue = name
        nameLabel.toolTip = name
        requestLabel.stringValue = "\(metrics.requestCount) 次"
        let tokenTotal = (metrics.inputTokens ?? 0)
            + (metrics.cachedInputTokens ?? 0)
            + (metrics.outputTokens ?? 0)
        let hasTokenDetail = metrics.inputTokens != nil
            || metrics.cachedInputTokens != nil
            || metrics.outputTokens != nil
        let valueText: String?
        if let usd = metrics.usageUSD {
            valueText = formatUSD(usd)
        } else if hasTokenDetail {
            valueText = formatTokenCount(tokenTotal) + " tok"
        } else {
            valueText = nil
        }
        amountLabel.isHidden = valueText == nil
        amountLabel.stringValue = valueText ?? ""
        // 悬停给出 token 三项明细，避免只有合计时无法核对
        amountLabel.toolTip = hasTokenDetail
            ? "输入 \(formatTokenCount(metrics.inputTokens ?? 0))"
                + " · 缓存 \(formatTokenCount(metrics.cachedInputTokens ?? 0))"
                + " · 输出 \(formatTokenCount(metrics.outputTokens ?? 0))"
            : nil
        setAccessibilityLabel(valueText.map { "\(name) \(metrics.requestCount) 次 \($0)" }
            ?? "\(name) \(metrics.requestCount) 次")
    }
}
