import AppKit
import NetworkMonitorCore

// MARK: - 余额卡

/// 余额卡 — 可用额度 hero / 内含额度进度 / 周期 / 已购额度 / 遗留计划限额
///
/// 与原型对齐：卡片内边距 10/11、垂直间距 7、hero 25pt 等宽半粗、轨道 4pt。
/// 空余额（`isEmpty`）显示「暂无额度数据」；未拿到数据时只显示 "—"。
final class BillingBalanceSectionView: NSView {

    private let card = MenuPanelCardView()
    private let innerStack = NSStackView()

    private let titleLabel = MenuPanelLabel.text("可用额度",
                                                 font: BillingPaneStyle.cardTitleFont,
                                                 color: BillingPaneStyle.secondaryText)
    /// 遗留计划说明入口（悬停提示；正常额度卡隐藏）
    private let metricHintButton = NSButton()
    /// 可用额度 hero 行（遗留计划按百分比限额时整块隐藏）
    private let heroRow = NSStackView()
    private let totalLabel = MenuPanelLabel.text("—", font: BillingPaneStyle.heroFont, color: .labelColor)
    private let heroNoteLabel = MenuPanelLabel.text("", font: BillingPaneStyle.subFont,
                                                    color: BillingPaneStyle.tertiaryText)
    private let includedRow: NSStackView
    private let includedValue: NSTextField
    private let includedTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.accentColor)
    private let periodLabel = MenuPanelLabel.text("", font: BillingPaneStyle.subFont,
                                                  color: BillingPaneStyle.tertiaryText)
    private let purchasedRow: NSStackView
    private let purchasedValue: NSTextField
    private let limitStack = NSStackView()
    private let emptyLabel = MenuPanelLabel.text("暂无额度数据", font: BillingPaneStyle.labelFont,
                                                 color: BillingPaneStyle.secondaryText)
    private var limitRows: [BillingLimitRow] = []

    // MARK: - 初始化

    init() {
        let included = Self.makeKeyValueRow(title: "内含额度")
        includedRow = included.row
        includedValue = included.value
        let purchased = Self.makeKeyValueRow(title: "已购额度")
        purchasedRow = purchased.row
        purchasedValue = purchased.value
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        heroRow.addArrangedSubview(totalLabel)
        heroRow.addArrangedSubview(heroNoteLabel)
        heroRow.orientation = .horizontal
        heroRow.alignment = .lastBaseline
        heroRow.spacing = 6
        heroNoteLabel.setContentHuggingPriority(.required, for: .horizontal)
        heroNoteLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 遗留计划：核心信息是会话/每周剩余百分比，金额与说明属于非核心，用「?」承载
        metricHintButton.image = NSImage(systemSymbolName: "questionmark.circle",
                                         accessibilityDescription: "额度说明")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        metricHintButton.isBordered = false
        metricHintButton.bezelStyle = .inline
        metricHintButton.contentTintColor = BillingPaneStyle.tertiaryText
        metricHintButton.toolTip = "该计划按百分比限额计费，不提供内含额度与购买余额"
        metricHintButton.setAccessibilityLabel("额度说明")
        metricHintButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            metricHintButton.widthAnchor.constraint(equalToConstant: 14),
            metricHintButton.heightAnchor.constraint(equalToConstant: 14),
        ])
        metricHintButton.isHidden = true

        let headerRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), metricHintButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        limitStack.orientation = .vertical
        limitStack.alignment = .leading
        limitStack.spacing = 7

        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 7
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        for view in [headerRow, heroRow, includedRow, includedTrack, periodLabel, purchasedRow,
                     limitStack, emptyLabel] {
            innerStack.addArrangedSubview(view)
        }

        card.addSubview(innerStack)
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            innerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            innerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -11),
            innerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            innerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11),
        ])
        for view in innerStack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: innerStack.widthAnchor).isActive = true
        }
        emptyLabel.isHidden = true
        limitStack.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据更新

    /// 更新余额卡（nil = 尚无成功数据）
    func update(balance: BillingBalance?) {
        guard let balance else {
            titleLabel.stringValue = "可用额度"
            metricHintButton.isHidden = true
            heroRow.isHidden = false
            totalLabel.stringValue = "—"
            heroNoteLabel.stringValue = ""
            emptyLabel.isHidden = true
            includedRow.isHidden = true
            includedTrack.isHidden = true
            periodLabel.isHidden = true
            purchasedRow.isHidden = true
            limitStack.isHidden = true
            return
        }

        // 遗留计划（无内含额度、只有百分比限额）：金额与计划说明属非核心信息，
        // 隐藏 hero 整块，只保留会话/每周限额；说明由标题右侧「?」承载
        let legacyPercentOnly = balance.included == nil && !balance.percentLimits.isEmpty
        titleLabel.stringValue = legacyPercentOnly ? "剩余额度" : "可用额度"
        metricHintButton.isHidden = !legacyPercentOnly
        heroRow.isHidden = legacyPercentOnly
        totalLabel.stringValue = balance.totalAvailableUSD.map { formatUSD($0) } ?? "—"
        heroNoteLabel.stringValue = Self.heroNote(for: balance)
        emptyLabel.isHidden = !balance.isEmpty || legacyPercentOnly

        if let included = balance.included {
            includedRow.isHidden = false
            includedTrack.isHidden = false
            includedValue.stringValue = "\(formatUSD(included.remainingUSD)) / \(formatUSD(included.allowanceUSD))"
            includedTrack.fraction = included.remainingFraction
            updatePeriod(included.period)
        } else {
            includedRow.isHidden = true
            includedTrack.isHidden = true
            periodLabel.isHidden = true
        }

        // 无内含额度时 hero 数字本身就是已购额度，下方不再重复一行
        purchasedRow.isHidden = balance.purchasedUSD == nil || balance.included == nil
        if let purchased = balance.purchasedUSD {
            purchasedValue.stringValue = formatUSD(purchased)
        }

        rebuildLimits(balance.percentLimits)
    }

    /// 周期信息：剩余天数 + 重置日；周期已结束显示明确文案
    private func updatePeriod(_ period: BillingPeriod?) {
        guard let period else {
            periodLabel.isHidden = true
            return
        }
        periodLabel.isHidden = false
        let now = Date()
        guard period.end > now else {
            periodLabel.stringValue = "周期已结束"
            return
        }
        let days = period.remainingDays(at: now)
        periodLabel.stringValue = "本周期剩余 \(days) 天 · \(Self.monthDayFormatter.string(from: period.end)) 重置"
    }

    /// 重建遗留计划限额行（session / weekly 等）
    private func rebuildLimits(_ limits: [BillingPercentLimit]) {
        for row in limitRows {
            limitStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        limitRows = limits.map { limit in
            let row = BillingLimitRow()
            row.update(limit: limit)
            return row
        }
        for row in limitRows {
            limitStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: limitStack.widthAnchor).isActive = true
        }
        limitStack.isHidden = limitRows.isEmpty
    }

    // MARK: - 文案

    /// hero 右侧说明：按实际持有的额度维度组合，避免「内含 + 已购」与实际不符
    private static func heroNote(for balance: BillingBalance) -> String {
        // 遗留计划（原型 D）：无内含额度、只有已购余额 + 百分比限额
        if balance.included == nil, balance.purchasedUSD != nil, !balance.percentLimits.isEmpty {
            return "遗留计划 · 按百分比限额"
        }
        if balance.included != nil, balance.purchasedUSD != nil { return "内含 + 已购" }
        if balance.included != nil {
            return balance.percentLimits.isEmpty ? "内含额度" : "内含额度 · 遗留计划"
        }
        if balance.purchasedUSD != nil {
            return balance.percentLimits.isEmpty ? "已购额度" : "已购额度 · 遗留计划"
        }
        return balance.percentLimits.isEmpty ? "" : "遗留计划 · 按百分比限额"
    }

    /// 键值行（左标题 + 右等宽数值）
    private static func makeKeyValueRow(title: String) -> (row: NSStackView, value: NSTextField) {
        let value = MenuPanelLabel.text("", font: BillingPaneStyle.monoFont, color: .labelColor)
        value.alignment = .right
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [MenuPanelLabel.text(title,
                                                          font: BillingPaneStyle.labelFont,
                                                          color: BillingPaneStyle.secondaryText),
                                      MenuPanelLabel.spacer(),
                                      value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return (row, value)
    }

    /// 重置日期（本地时区 M/d）
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

// MARK: - 遗留计划限额行

/// 遗留计划限额行 — 标题 + 剩余百分比 + 绝对值明细 + 分级进度条 + 重置时间
///
/// 进度条颜色分级：≥50% 强调色、≥25% 橙色、<25% 红色（与原型一致）。
/// 绝对值明细行（如「已用 76,412 / 150,000 credits」）仅在 provider 给出
/// `usedAmount` 与 `limitAmount` 时显示；只给百分比的计划该行隐藏。
final class BillingLimitRow: NSView {

    private let titleLabel = MenuPanelLabel.text("", font: BillingPaneStyle.labelFont,
                                                 color: BillingPaneStyle.secondaryText)
    private let valueLabel = MenuPanelLabel.text("", font: BillingPaneStyle.monoFont, color: .labelColor)
    /// 绝对值明细（credits 等非金额计量；无明细时隐藏）
    private let usageLabel = MenuPanelLabel.text("", font: BillingPaneStyle.subFont,
                                                 color: BillingPaneStyle.tertiaryText)
    private let track = MenuPanelTrackView(fillColor: MenuPanelStyle.accentColor)
    private let resetLabel = MenuPanelLabel.text("", font: BillingPaneStyle.subFont,
                                                 color: BillingPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), valueLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8

        // 明细行紧贴标题行、位于进度条之上；重置时间仍在最下
        let stack = NSStackView(views: [titleRow, usageLabel, track, resetLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        usageLabel.isHidden = true
        resetLabel.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新单条限额
    func update(limit: BillingPercentLimit) {
        titleLabel.stringValue = limit.title
        let percent = formatPercent(limit.remainingFraction)
        valueLabel.stringValue = "剩余 " + percent
        track.fraction = limit.remainingFraction
        track.fillColor = Self.fillColor(for: limit.remainingFraction)
        // 绝对值明细：两端都有值才渲染（Ollama 遗留计划只给百分比，该行保持隐藏）
        let usage = limit.hasAmountDetail
            ? formatLimitUsage(used: limit.usedAmount, limit: limit.limitAmount, unit: limit.unitLabel)
            : nil
        usageLabel.stringValue = usage ?? ""
        usageLabel.isHidden = usage == nil
        resetLabel.stringValue = limit.resetsAt.map { formatShortDateTime($0) + " 重置" } ?? ""
        resetLabel.isHidden = limit.resetsAt == nil
        setAccessibilityLabel(usage.map { "\(limit.title) 剩余 \(percent)，\($0)" }
            ?? "\(limit.title) 剩余 \(percent)")
    }

    /// 剩余比例 → 进度条颜色（分级阈值与原型一致）
    private static func fillColor(for fraction: Double) -> NSColor {
        if fraction >= 0.5 { return MenuPanelStyle.accentColor }
        if fraction >= 0.25 { return .systemOrange }
        return .systemRed
    }
}
