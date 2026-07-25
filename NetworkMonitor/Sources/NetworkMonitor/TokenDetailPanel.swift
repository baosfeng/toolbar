import AppKit
import NetworkMonitorCore
import SwiftUI

// MARK: - 可点击行视图

/// 可点击的菜单行视图，带悬停高亮效果
private final class ClickableRow: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let gesture = NSClickGestureRecognizer(target: self, action: #selector(didClick))
        gesture.numberOfClicksRequired = 1
        addGestureRecognizer(gesture)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func didClick() {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }
}

// MARK: - Token 用量详情面板

/// Token 用量详情面板 — iOS 风格设计
final class TokenDetailPanel: NSPanel {

    // MARK: - 字体常量

    private static let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let bigNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
    private static let bodyFont = NSFont.systemFont(ofSize: 12)
    private static let captionFont = NSFont.systemFont(ofSize: 10)

    // MARK: - 颜色

    private static let tokenColor = NSColor.systemBlue
    private static let costColor = NSColor.systemOrange
    private static let cardBg = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
    private static let barColor = NSColor.systemBlue.withAlphaComponent(0.7)
    private static let barActiveColor = NSColor.systemBlue
    private static let barBg = NSColor.separatorColor.withAlphaComponent(0.2)
    private static let secondaryText = NSColor.secondaryLabelColor

    // MARK: - 布局常量

    private static let edge: CGFloat = 16
    private static let cardSpacing: CGFloat = 10
    private static let cardPadding: CGFloat = 14
    private static let cornerRadius: CGFloat = 10
    private static let panelWidth: CGFloat = 380
    private static let panelHeight: CGFloat = 540

    // MARK: - 子视图

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let summaryTokensLabel = NSTextField(labelWithString: "—")
    private let summaryCostLabel = NSTextField(labelWithString: "—")
    private let modelStack = NSStackView()
    private let hourlyStack = NSStackView()
    private let historyStack = NSStackView()
    private let dateLabel = NSTextField(labelWithString: "今日")

    // MARK: - 数据

    private let provider: TokenUsageProvider
    private var currentDate: String

    // MARK: - 初始化

    init(provider: TokenUsageProvider) {
        self.provider = provider
        self.currentDate = Self.todayString()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Token 用量"
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        setupUI()
        reloadData()
    }

    // MARK: - 刷新

    func reloadData() {
        loadSummary()
        loadHourly(dateString: currentDate)
        loadHistory()
    }

    func switchToDate(_ dateString: String) {
        currentDate = dateString
        dateLabel.stringValue = dateString == Self.todayString() ? "今日" : Self.shortDate(dateString)
        loadHourly(dateString: dateString)
    }

    // MARK: - 数据加载

    private func loadSummary() {
        let summary = provider.fetchTodaySummary()
        summaryTokensLabel.stringValue = Self.formatTokens(summary.totalTokens)
        summaryCostLabel.stringValue = Self.formatCost(summary.totalCost)

        modelStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if summary.byModel.isEmpty {
            let empty = NSTextField(labelWithString: "暂无数据")
            empty.font = Self.bodyFont
            empty.textColor = Self.secondaryText
            modelStack.addArrangedSubview(empty)
        } else {
            for mu in summary.byModel {
                modelStack.addArrangedSubview(Self.makeModelRow(model: mu.model, tokens: mu.totalTokens, cost: mu.cost))
            }
            // 模型占比环形图
            let pieView = TokenModelPieChart(byModel: summary.byModel)
            let pieHosting = NSHostingView(rootView: pieView)
            pieHosting.translatesAutoresizingMaskIntoConstraints = false
            modelStack.addArrangedSubview(pieHosting)
        }
    }

    private func loadHourly(dateString: String) {
        let data = provider.fetchHourlyBreakdown(dateString: dateString)

        hourlyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let chartView = TokenHourlyChartView(data: data)
        let hosting = NSHostingView(rootView: chartView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hourlyStack.addArrangedSubview(hosting)
    }

    private func loadHistory() {
        let data = provider.fetchDailyHistory(days: 7)

        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let chartView = TokenHistoryChartView(data: data)
        let hosting = NSHostingView(rootView: chartView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        historyStack.addArrangedSubview(hosting)
    }

    // MARK: - UI 构建

    private func setupUI() {
        // 毛玻璃背景
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView = visualEffect

        // 主内容区
        contentStack.orientation = .vertical
        contentStack.spacing = Self.cardSpacing
        contentStack.edgeInsets = NSEdgeInsets(top: 44, left: Self.edge, bottom: Self.edge, right: Self.edge)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        // ScrollView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentStack

        visualEffect.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -10)
        ])

        // ── 今日汇总卡片 ──
        contentStack.addArrangedSubview(Self.makeSectionTitle("今日汇总"))

        let summaryCard = Self.makeCard()
        let summaryInner = NSStackView(views: [
            Self.makeSummaryRow(icon: "repeat", label: "总 Token", textField: summaryTokensLabel, color: Self.tokenColor),
            Self.makeSummaryRow(icon: "dollarsign.circle", label: "总花费", textField: summaryCostLabel, color: Self.costColor)
        ])
        summaryInner.orientation = .horizontal
        summaryInner.spacing = 12
        summaryInner.distribution = .fillEqually

        let modelLabel = Self.makeCaption("按模型")
        modelStack.orientation = .vertical
        modelStack.spacing = 4

        let summaryVStack = NSStackView(views: [summaryInner, Self.makeSeparator(), modelLabel, modelStack])
        summaryVStack.orientation = .vertical
        summaryVStack.spacing = 8
        summaryVStack.edgeInsets = NSEdgeInsets(top: Self.cardPadding, left: Self.cardPadding,
                                                bottom: Self.cardPadding, right: Self.cardPadding)
        summaryCard.addSubview(summaryVStack)
        summaryVStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            summaryVStack.topAnchor.constraint(equalTo: summaryCard.topAnchor),
            summaryVStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor),
            summaryVStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor),
            summaryVStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor)
        ])
        contentStack.addArrangedSubview(summaryCard)

        // ── 逐时消耗卡片 ──
        let hourlyHeader = NSStackView(views: [Self.makeSectionTitle("逐时消耗"), dateLabel])
        dateLabel.font = Self.bodyFont
        dateLabel.textColor = Self.secondaryText
        hourlyHeader.orientation = .horizontal
        contentStack.addArrangedSubview(hourlyHeader)

        let hourlyCard = Self.makeCard()
        hourlyStack.orientation = .vertical
        hourlyStack.spacing = 2
        hourlyStack.edgeInsets = NSEdgeInsets(top: Self.cardPadding, left: Self.cardPadding,
                                              bottom: Self.cardPadding, right: Self.cardPadding)

        hourlyCard.addSubview(hourlyStack)
        hourlyStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hourlyStack.topAnchor.constraint(equalTo: hourlyCard.topAnchor),
            hourlyStack.leadingAnchor.constraint(equalTo: hourlyCard.leadingAnchor),
            hourlyStack.trailingAnchor.constraint(equalTo: hourlyCard.trailingAnchor),
            hourlyStack.bottomAnchor.constraint(equalTo: hourlyCard.bottomAnchor)
        ])
        contentStack.addArrangedSubview(hourlyCard)

        // ── 近7日历史卡片 ──
        contentStack.addArrangedSubview(Self.makeSectionTitle("近7日"))
        let historyCard = Self.makeCard()
        historyStack.orientation = .vertical
        historyStack.spacing = 2
        historyStack.edgeInsets = NSEdgeInsets(top: Self.cardPadding, left: Self.cardPadding,
                                               bottom: Self.cardPadding, right: Self.cardPadding)

        historyCard.addSubview(historyStack)
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            historyStack.topAnchor.constraint(equalTo: historyCard.topAnchor),
            historyStack.leadingAnchor.constraint(equalTo: historyCard.leadingAnchor),
            historyStack.trailingAnchor.constraint(equalTo: historyCard.trailingAnchor),
            historyStack.bottomAnchor.constraint(equalTo: historyCard.bottomAnchor)
        ])
        contentStack.addArrangedSubview(historyCard)

        // 底部留白
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        contentStack.addArrangedSubview(spacer)

        setContentSize(NSSize(width: Self.panelWidth, height: Self.panelHeight))
    }

    // MARK: - 工厂方法

    private static func makeCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = Self.cornerRadius
        v.layer?.backgroundColor = Self.cardBg.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private static func makeSectionTitle(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = Self.titleFont
        l.textColor = .labelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private static func makeCaption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = Self.captionFont
        l.textColor = Self.secondaryText
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private static func makeSeparator() -> NSView {
        let l = NSView()
        l.wantsLayer = true
        l.layer?.backgroundColor = NSColor.separatorColor.cgColor
        l.translatesAutoresizingMaskIntoConstraints = false
        l.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return l
    }

    private static func makeSummaryRow(icon: String, label: String,
                                       textField: NSTextField, color: NSColor) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: label) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            iconView.image = img.withSymbolConfiguration(cfg) ?? img
            iconView.contentTintColor = color
        }

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = Self.captionFont
        titleLabel.textColor = Self.secondaryText

        textField.font = Self.bigNumberFont
        textField.textColor = color
        textField.alignment = .center

        let vStack = NSStackView(views: [iconView, titleLabel, textField])
        vStack.orientation = .vertical
        vStack.spacing = 2
        vStack.alignment = .centerX
        vStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            vStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 4),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private static func makeModelRow(model: String, tokens: Int, cost: Double) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: Self.shortModelName(model))
        nameLabel.font = Self.bodyFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        let tokensLabel = NSTextField(labelWithString: Self.formatTokens(tokens))
        tokensLabel.font = Self.numberFont
        tokensLabel.textColor = Self.tokenColor
        tokensLabel.alignment = NSTextAlignment.right

        let costLabel = NSTextField(labelWithString: Self.formatCost(cost))
        costLabel.font = Self.numberFont
        costLabel.textColor = Self.costColor
        costLabel.alignment = NSTextAlignment.right

        [nameLabel, tokensLabel, costLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: tokensLabel.leadingAnchor, constant: -8),
            tokensLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tokensLabel.widthAnchor.constraint(equalToConstant: 80),
            tokensLabel.trailingAnchor.constraint(equalTo: costLabel.leadingAnchor, constant: -8),
            costLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            costLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            costLabel.widthAnchor.constraint(equalToConstant: 70),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
        ])
        return row
    }

    private static func makeHourHeader() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let hourL = Self.makeCaption("时间")
        let barL = Self.makeCaption("用量")
        let tokensL = Self.makeCaption("Tokens"); tokensL.alignment = .right
        let costL = Self.makeCaption("花费"); costL.alignment = .right

        [hourL, barL, tokensL, costL].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }

        NSLayoutConstraint.activate([
            hourL.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            hourL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            hourL.widthAnchor.constraint(equalToConstant: 36),
            barL.leadingAnchor.constraint(equalTo: hourL.trailingAnchor, constant: 6),
            barL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            barL.trailingAnchor.constraint(equalTo: tokensL.leadingAnchor, constant: -6),
            tokensL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tokensL.widthAnchor.constraint(equalToConstant: 80),
            tokensL.trailingAnchor.constraint(equalTo: costL.leadingAnchor, constant: -6),
            costL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            costL.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            costL.widthAnchor.constraint(equalToConstant: 60),
            row.heightAnchor.constraint(equalToConstant: 20)
        ])
        return row
    }

    private static func makeHourRow(entry: HourlyTokenUsage, maxTokens: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let hourLabel = NSTextField(labelWithString: "\(entry.hour)时")
        hourLabel.font = Self.captionFont
        hourLabel.textColor = NSColor.labelColor
        hourLabel.alignment = NSTextAlignment.center

        let barContainer = NSView()
        barContainer.wantsLayer = true
        barContainer.layer?.cornerRadius = 3
        barContainer.layer?.backgroundColor = Self.barBg.cgColor
        barContainer.translatesAutoresizingMaskIntoConstraints = false

        let barFill = NSView()
        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 3
        barFill.layer?.backgroundColor = (entry.totalTokens > 0 ? Self.barColor : .clear).cgColor
        barFill.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(barFill)

        let fraction = maxTokens > 0 ? CGFloat(entry.totalTokens) / CGFloat(maxTokens) : 0
        let barWidth = max(4, fraction * 120)

        NSLayoutConstraint.activate([
            barFill.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barContainer.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            barFill.widthAnchor.constraint(equalToConstant: barWidth)
        ])

        let tokensLabel = NSTextField(labelWithString: Self.formatTokens(entry.totalTokens))
        tokensLabel.font = Self.numberFont
        tokensLabel.textColor = NSColor.labelColor
        tokensLabel.alignment = NSTextAlignment.right

        let costLabel = NSTextField(labelWithString: Self.formatCost(entry.cost))
        costLabel.font = Self.numberFont
        costLabel.textColor = Self.costColor
        costLabel.alignment = NSTextAlignment.right

        [hourLabel, barContainer, tokensLabel, costLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }

        NSLayoutConstraint.activate([
            hourLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            hourLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            hourLabel.widthAnchor.constraint(equalToConstant: 36),
            barContainer.leadingAnchor.constraint(equalTo: hourLabel.trailingAnchor, constant: 6),
            barContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            barContainer.heightAnchor.constraint(equalToConstant: 10),
            barContainer.trailingAnchor.constraint(equalTo: tokensLabel.leadingAnchor, constant: -6),
            tokensLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tokensLabel.widthAnchor.constraint(equalToConstant: 80),
            tokensLabel.trailingAnchor.constraint(equalTo: costLabel.leadingAnchor, constant: -6),
            costLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            costLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            costLabel.widthAnchor.constraint(equalToConstant: 60),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])
        return row
    }

    private static func makeHistoryHeader() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let dateL = Self.makeCaption("日期")
        let barL = Self.makeCaption("用量")
        let tokensL = Self.makeCaption("Tokens"); tokensL.alignment = .right
        let costL = Self.makeCaption("花费"); costL.alignment = .right

        [dateL, barL, tokensL, costL].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }

        NSLayoutConstraint.activate([
            dateL.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dateL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dateL.widthAnchor.constraint(equalToConstant: 56),
            barL.leadingAnchor.constraint(equalTo: dateL.trailingAnchor, constant: 6),
            barL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            barL.trailingAnchor.constraint(equalTo: tokensL.leadingAnchor, constant: -6),
            tokensL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tokensL.widthAnchor.constraint(equalToConstant: 80),
            tokensL.trailingAnchor.constraint(equalTo: costL.leadingAnchor, constant: -6),
            costL.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            costL.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            costL.widthAnchor.constraint(equalToConstant: 60),
            row.heightAnchor.constraint(equalToConstant: 20)
        ])
        return row
    }

    private static func makeDayRow(entry: DailyTokenUsage, maxTokens: Int, onClick: @escaping () -> Void) -> NSView {
        let row = ClickableRow()
        row.onClick = onClick
        row.translatesAutoresizingMaskIntoConstraints = false

        let dateLabel = NSTextField(labelWithString: Self.shortDate(entry.date))
        dateLabel.font = Self.bodyFont
        dateLabel.textColor = NSColor.labelColor

        let barContainer = NSView()
        barContainer.wantsLayer = true
        barContainer.layer?.cornerRadius = 3
        barContainer.layer?.backgroundColor = Self.barBg.cgColor
        barContainer.translatesAutoresizingMaskIntoConstraints = false

        let barFill = NSView()
        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 3
        barFill.layer?.backgroundColor = (entry.totalTokens > 0 ? Self.barColor : .clear).cgColor
        barFill.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(barFill)

        let fraction = maxTokens > 0 ? CGFloat(entry.totalTokens) / CGFloat(maxTokens) : 0
        let barWidth = max(4, fraction * 100)

        NSLayoutConstraint.activate([
            barFill.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barContainer.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            barFill.widthAnchor.constraint(equalToConstant: barWidth)
        ])

        let tokensLabel = NSTextField(labelWithString: Self.formatTokens(entry.totalTokens))
        tokensLabel.font = Self.numberFont
        tokensLabel.textColor = NSColor.labelColor
        tokensLabel.alignment = NSTextAlignment.right

        let costLabel = NSTextField(labelWithString: Self.formatCost(entry.cost))
        costLabel.font = Self.numberFont
        costLabel.textColor = Self.costColor
        costLabel.alignment = NSTextAlignment.right

        [dateLabel, barContainer, tokensLabel, costLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }

        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dateLabel.widthAnchor.constraint(equalToConstant: 56),
            barContainer.leadingAnchor.constraint(equalTo: dateLabel.trailingAnchor, constant: 6),
            barContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            barContainer.heightAnchor.constraint(equalToConstant: 10),
            barContainer.trailingAnchor.constraint(equalTo: tokensLabel.leadingAnchor, constant: -6),
            tokensLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tokensLabel.widthAnchor.constraint(equalToConstant: 80),
            tokensLabel.trailingAnchor.constraint(equalTo: costLabel.leadingAnchor, constant: -6),
            costLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            costLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            costLabel.widthAnchor.constraint(equalToConstant: 60),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])

        return row
    }

    // MARK: - 辅助

    private static func formatTokens(_ count: Int) -> String {
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }

    private static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return String(format: "¥%.4f", cost) }
        if cost < 1 { return String(format: "¥%.3f", cost) }
        return String(format: "¥%.2f", cost)
    }

    private static func shortModelName(_ model: String) -> String {
        if model.lowercased().contains("gpt-4o") { return "GPT-4o" }
        if model.lowercased().contains("gpt-4") { return "GPT-4" }
        if model.lowercased().contains("gpt-3.5") || model.lowercased().contains("gpt35") { return "GPT-3.5" }
        if model.lowercased().contains("claude-3.5") || model.lowercased().contains("claude-35") { return "Claude 3.5" }
        if model.lowercased().contains("claude-3") { return "Claude 3" }
        if model.lowercased().contains("claude") { return "Claude" }
        if model.lowercased().contains("gemini") { return "Gemini" }
        if model.lowercased().contains("deepseek") { return "DeepSeek" }
        if model.count > 12 { return String(model.prefix(10)) + "…" }
        return model
    }

    private static func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        return "\(Int(parts[1])!)/\(Int(parts[2])!)"
    }

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
