import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度族格（与 Token 分族卡同构）

/// 额度格 —— 「数值（19pt）+ 单位（11pt）+ 名称 + 3pt 进度条 + 重置时间」
///
/// 与 Token 页「标题 + 大数值 + 一行辅助」的分族卡同构；两页同一套字号梯度，
/// 所以打开两页看到的最大数字不会像改前那样差 1.5 倍（16 vs 24）。
final class BillingLimitCellView: NSView {

    private let valueLabel = MenuPanelLabel.text("—", font: PaneCardStyle.cardValueFont,
                                                 color: PaneCardStyle.primaryText)
    private let unitLabel = MenuPanelLabel.text("%", font: PaneCardStyle.cardValueUnitFont,
                                                color: PaneCardStyle.tertiaryText)
    private let titleLabel = MenuPanelLabel.text("", font: PaneCardStyle.rowNameFont,
                                                 color: PaneCardStyle.tertiaryText)
    private let barView = BillingProgressBarView()
    /// 状态角标（如「已限流」）—— 与警告墨色同源，小字过 4.5:1
    private let badgeLabel = MenuPanelLabel.text("", font: PaneCardStyle.axisFont,
                                                 color: PaneCardStyle.warnInk)
    private let resetLabel = MenuPanelLabel.text("", font: PaneCardStyle.axisFont,
                                                 color: PaneCardStyle.tertiaryText)
    /// 角标 + 重置时间：1–2 列同行，3 列窄格改上下两行
    private let resetStack = NSStackView()

    private var badgeText: String?
    private var isCompact = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [valueLabel, unitLabel, titleLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .lastBaseline
        topRow.spacing = 2
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)
        unitLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        // 数值与单位紧贴（2pt），单位与名称之间留 4pt，读作「95 % 会话」
        topRow.setCustomSpacing(2, after: valueLabel)
        topRow.setCustomSpacing(4, after: unitLabel)

        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        resetStack.orientation = .horizontal
        resetStack.alignment = .firstBaseline
        resetStack.spacing = 3
        resetStack.addArrangedSubview(badgeLabel)
        resetStack.addArrangedSubview(resetLabel)

        let stack = NSStackView(views: [topRow, titleLabel, barView, resetStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PaneCardStyle.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            barView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据更新

    /// 更新一格限额
    func update(limit: BillingPercentLimit, compact: Bool = false) {
        barView.isHidden = false
        applyPercent(limit.remainingFraction)
        titleLabel.stringValue = limit.title
        barView.update(fraction: limit.remainingFraction,
                       level: Self.level(for: limit.remainingFraction))
        badgeText = limit.badge
        isCompact = compact
        resetLabel.stringValue = Self.resetText(limit.resetsAt)
        syncResetRow(hasReset: limit.resetsAt != nil)
        setAccessibilityLabel(Self.accessibilityText(title: limit.title,
                                                     percent: formatPercent(limit.remainingFraction),
                                                     badge: limit.badge))
    }

    /// 金额型余额（provider 只给可用金额、没有百分比限额）
    func update(amount: String, title: String) {
        barView.isHidden = true
        let split = PaneValueFormatting.split(amount)
        valueLabel.stringValue = split.number
        unitLabel.stringValue = split.unit
        applyValueTier(for: split.number)
        titleLabel.stringValue = title
        badgeText = nil
        isCompact = false
        syncResetRow(hasReset: false)
        setAccessibilityLabel("\(title) \(amount)")
    }

    /// 恢复占位态
    func clear() {
        barView.isHidden = false
        valueLabel.stringValue = "—"
        unitLabel.stringValue = ""
        titleLabel.stringValue = ""
        barView.update(fraction: 0, level: .normal)
        badgeText = nil
        isCompact = false
        resetLabel.stringValue = ""
        syncResetRow(hasReset: false)
        setAccessibilityLabel("暂无额度数据")
    }

    /// 剩余比例 → 数值段 + 单位段（百分比也分列，与 Token 页数值语法一致）
    private func applyPercent(_ fraction: Double) {
        let split = PaneValueFormatting.split(formatPercent(fraction))
        valueLabel.stringValue = split.number
        unitLabel.stringValue = split.unit
        applyValueTier(for: split.number)
    }

    /// 数值过长时降一档字号（原值一个字符都不丢，见 PaneValueSizing）
    private func applyValueTier(for number: String) {
        switch PaneValueSizing.tier(forNumber: number) {
        case .regular: valueLabel.font = PaneCardStyle.cardValueFont
        case .compact: valueLabel.font = PaneCardStyle.cardValueCompactFont
        case .dense:   valueLabel.font = PaneCardStyle.cardValueDenseFont
        }
    }

    private func syncResetRow(hasReset: Bool) {
        resetStack.orientation = isCompact ? .vertical : .horizontal
        resetStack.alignment = isCompact ? .leading : .firstBaseline
        resetStack.spacing = isCompact ? 1 : 3
        resetLabel.isHidden = !hasReset
        if let badgeText {
            if isCompact || !hasReset {
                badgeLabel.stringValue = badgeText
            } else {
                badgeLabel.stringValue = BillingLimitLayout.inlineBadge(badgeText)
            }
            badgeLabel.isHidden = false
        } else {
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = !isCompact
        }
        resetStack.isHidden = !isCompact && !hasReset && badgeText == nil
    }

    // MARK: - 文案

    private static func accessibilityText(title: String, percent: String, badge: String?) -> String {
        let base = "\(title) 剩余 \(percent)"
        guard let badge else { return base }
        return base + " " + badge
    }

    /// 重置时间：当天只给时分，跨天补日期
    static func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm 重置" : "M/d HH:mm 重置"
        return formatter.string(from: date)
    }

    /// 剩余比例 → 告警级别（<20% 红、<50% 橙）
    static func level(for fraction: Double) -> BillingProgressBarView.Level {
        if fraction < 0.2 { return .danger }
        if fraction < 0.5 { return .warn }
        return .normal
    }
}
