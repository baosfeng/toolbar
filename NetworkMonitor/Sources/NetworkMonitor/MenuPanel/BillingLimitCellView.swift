import AppKit
import NetworkMonitorCore

// MARK: - 双列额度格

/// 双列额度格 — 大号百分比 + 额度名称 + 细进度条 + 重置时间
///
/// 聚合视图里每个 provider 一行放两格（会话 / 每周），把原先「标题 + 条 + 时间」三行压成三行双列，
/// 在 320pt 浮层里同时容纳多个 provider。
final class BillingLimitCellView: NSView {

    private let valueLabel = MenuPanelLabel.text("—", font: BillingPaneStyle.cellValueFont,
                                                 color: .labelColor)
    private let titleLabel = MenuPanelLabel.text("", font: BillingPaneStyle.cellTitleFont,
                                                 color: BillingPaneStyle.tertiaryText)
    private let barView = BillingProgressBarView()
    private let resetLabel = MenuPanelLabel.text("", font: BillingPaneStyle.resetFont,
                                                 color: BillingPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [valueLabel, titleLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .lastBaseline
        topRow.spacing = 4
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [topRow, barView, resetLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            barView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新一格限额
    func update(limit: BillingPercentLimit) {
        barView.isHidden = false
        valueLabel.stringValue = formatPercent(limit.remainingFraction)
        titleLabel.stringValue = limit.title
        barView.update(fraction: limit.remainingFraction,
                       level: Self.level(for: limit.remainingFraction))
        resetLabel.stringValue = Self.resetText(limit.resetsAt)
        resetLabel.isHidden = limit.resetsAt == nil
        setAccessibilityLabel("\(limit.title) 剩余 \(formatPercent(limit.remainingFraction))")
    }

    /// 金额型余额（provider 只给可用金额、没有百分比限额）
    func update(amount: String, title: String) {
        barView.isHidden = true
        valueLabel.stringValue = amount
        titleLabel.stringValue = title
        resetLabel.isHidden = true
        setAccessibilityLabel("\(title) \(amount)")
    }

    /// 恢复占位态（无数据 / 未配置）
    func clear() {
        barView.isHidden = false
        valueLabel.stringValue = "—"
        titleLabel.stringValue = ""
        barView.update(fraction: 0, level: .normal)
        resetLabel.stringValue = ""
        resetLabel.isHidden = true
        setAccessibilityLabel("暂无额度数据")
    }

    // MARK: - 文案

    /// 重置时间：当天只给时分，跨天补日期
    static func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date) + " 重置"
    }

    /// 剩余比例 → 告警级别（与原型阈值一致：<50% 橙、<20% 红）
    static func level(for fraction: Double) -> BillingProgressBarView.Level {
        if fraction < 0.2 { return .danger }
        if fraction < 0.5 { return .warn }
        return .normal
    }
}