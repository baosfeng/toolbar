import AppKit
import NetworkMonitorCore

// MARK: - 额度格

/// 额度格 — 大号百分比 + 额度名称 + 细进度条 + 状态角标 / 重置时间
///
/// 聚合视图里每个 provider 一行排 1–3 格（窗口数量由 provider 决定），
/// 把原先「标题 + 条 + 时间」三行压成紧凑单元格，在 320pt 浮层里同时容纳多个 provider。
final class BillingLimitCellView: NSView {

    private let valueLabel = MenuPanelLabel.text("—", font: BillingPaneStyle.cellValueFont,
                                                 color: .labelColor)
    private let titleLabel = MenuPanelLabel.text("", font: BillingPaneStyle.cellTitleFont,
                                                 color: BillingPaneStyle.tertiaryText)
    private let barView = BillingProgressBarView()
    /// 状态角标（如「已限流」）— 用告警红，与错误条同一语义色，不引入新配色
    private let badgeLabel = MenuPanelLabel.text("", font: BillingPaneStyle.resetFont,
                                                 color: .systemRed)
    private let resetLabel = MenuPanelLabel.text("", font: BillingPaneStyle.resetFont,
                                                 color: BillingPaneStyle.tertiaryText)
    /// 角标 + 重置时间：1–2 列同行（「已限流 · 10/26 08:00 重置」），3 列窄格改上下两行
    private let resetStack = NSStackView()

    /// 当前角标文案（nil = 正常）
    private var badgeText: String?
    /// 是否三列窄格（每列约 86pt，角标与重置时间同行必然截断）
    private var isCompact = false

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

        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        resetStack.orientation = .horizontal
        resetStack.alignment = .firstBaseline
        resetStack.spacing = 3
        resetStack.addArrangedSubview(badgeLabel)
        resetStack.addArrangedSubview(resetLabel)

        let stack = NSStackView(views: [topRow, barView, resetStack])
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

    // MARK: - 数据更新

    /// 更新一格限额
    ///
    /// - Parameters:
    ///   - limit: 限额数据（含状态角标）
    ///   - compact: 三列窄格时为 true —— 角标独占一行，避免与重置时间挤在同一行被截断
    func update(limit: BillingPercentLimit, compact: Bool = false) {
        barView.isHidden = false
        valueLabel.stringValue = formatPercent(limit.remainingFraction)
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
        valueLabel.stringValue = amount
        titleLabel.stringValue = title
        badgeText = nil
        isCompact = false
        syncResetRow(hasReset: false)
        setAccessibilityLabel("\(title) \(amount)")
    }

    /// 恢复占位态（无数据 / 未配置）
    func clear() {
        barView.isHidden = false
        valueLabel.stringValue = "—"
        titleLabel.stringValue = ""
        barView.update(fraction: 0, level: .normal)
        badgeText = nil
        isCompact = false
        resetLabel.stringValue = ""
        syncResetRow(hasReset: false)
        setAccessibilityLabel("暂无额度数据")
    }

    /// 同步角标 / 重置行
    ///
    /// 窄格即使没有角标也保留角标行：同排三格的百分比基线才不会因角标出现与否而错位。
    private func syncResetRow(hasReset: Bool) {
        resetStack.orientation = isCompact ? .vertical : .horizontal
        resetStack.alignment = isCompact ? .leading : .firstBaseline
        resetStack.spacing = isCompact ? 1 : 3
        resetLabel.isHidden = !hasReset
        if let badgeText {
            // 同行时用间隔点衔接，读作「已限流 · 10/26 08:00 重置」；无重置时间则只显示角标
            if isCompact || !hasReset {
                badgeLabel.stringValue = badgeText
            } else {
                badgeLabel.stringValue = "\(badgeText) ·"
            }
            badgeLabel.isHidden = false
        } else {
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = !isCompact
        }
        resetStack.isHidden = !isCompact && !hasReset && badgeText == nil
    }

    // MARK: - 文案

    /// 无障碍标签：带上角标，读屏也能听到「已限流」
    private static func accessibilityText(title: String, percent: String, badge: String?) -> String {
        let base = "\(title) 剩余 \(percent)"
        guard let badge else { return base }
        return "\(base) \(badge)"
    }

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