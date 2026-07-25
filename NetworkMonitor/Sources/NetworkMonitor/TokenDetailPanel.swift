import AppKit
import NetworkMonitorCore
import SwiftUI

// MARK: - Token 用量详情面板

/// 漂亮的 Token 用量详情面板 — 独立窗口，完整图表展示
final class TokenDetailPanel: NSPanel {

    // MARK: - 字体

    private static let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let bodyFont = NSFont.systemFont(ofSize: 12)
    private static let captionFont = NSFont.systemFont(ofSize: 10)

    // MARK: - 布局

    private static let edge: CGFloat = 16
    private static let cardSpacing: CGFloat = 10
    private static let cardPadding: CGFloat = 14
    private static let cornerRadius: CGFloat = 10
    private static let cardBg = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
    private static let panelWidth: CGFloat = 420
    private static let panelHeight: CGFloat = 560

    // MARK: - 子视图

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let summaryTokensLabel = NSTextField(labelWithString: "—")
    private let summaryCostLabel = NSTextField(labelWithString: "—")
    private let modelSummaryStack = NSStackView()
    private let hourlyChartHosting = NSHostingView(rootView: AnyView(EmptyView()))
    private let historyChartHosting = NSHostingView(rootView: AnyView(EmptyView()))

    // MARK: - 数据

    private let provider: TokenUsageProvider

    // MARK: - 初始化

    init(provider: TokenUsageProvider) {
        self.provider = provider

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
        let summary = provider.fetchTodaySummary()
        let hourly = provider.fetchHourlyBreakdown()
        let history = provider.fetchDailyHistory(days: 7)

        // 更新汇总数字
        summaryTokensLabel.stringValue = Self.formatTokens(summary.totalTokens)
        summaryCostLabel.stringValue = Self.formatCost(summary.totalCost)

        // 更新模型汇总
        modelSummaryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if summary.byModel.isEmpty {
            let empty = NSTextField(labelWithString: "暂无数据")
            empty.font = Self.bodyFont
            empty.textColor = NSColor.secondaryLabelColor
            modelSummaryStack.addArrangedSubview(empty)
        } else {
            for mu in summary.byModel {
                modelSummaryStack.addArrangedSubview(makeModelRow(mu))
            }
            // 模型占比环形图
            let pieView = TokenModelPieChart(byModel: summary.byModel)
            let pieHosting = NSHostingView(rootView: pieView)
            pieHosting.translatesAutoresizingMaskIntoConstraints = false
            modelSummaryStack.addArrangedSubview(pieHosting)
        }

        // 更新逐时图表
        let hourlyView = TokenHourlyChartView(data: hourly)
        hourlyChartHosting.rootView = AnyView(hourlyView)

        // 更新历史图表
        let historyView = TokenHistoryChartView(data: history)
        historyChartHosting.rootView = AnyView(historyView)
    }

    // MARK: - UI 构建

    private func setupUI() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView = visualEffect

        contentStack.orientation = .vertical
        contentStack.spacing = Self.cardSpacing
        contentStack.edgeInsets = NSEdgeInsets(top: 44, left: Self.edge, bottom: Self.edge, right: Self.edge)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

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

        // ──────── 今日汇总卡片 ────────
        contentStack.addArrangedSubview(Self.sectionTitle("今日汇总"))

        let summaryCard = Self.makeCard()
        let innerRow = NSStackView(views: [
            Self.makeBigNumber(icon: "repeat", label: "总 Token", textField: summaryTokensLabel, color: .systemBlue),
            Self.makeBigNumber(icon: "dollarsign.circle", label: "总花费", textField: summaryCostLabel, color: .systemOrange)
        ])
        innerRow.orientation = NSUserInterfaceLayoutOrientation.horizontal
        innerRow.spacing = 12
        innerRow.distribution = NSStackView.Distribution.fillEqually

        let modelLabel = NSTextField(labelWithString: "按模型")
        modelLabel.font = Self.captionFont
        modelLabel.textColor = NSColor.secondaryLabelColor

        modelSummaryStack.orientation = .vertical
        modelSummaryStack.spacing = 4

        let vStack = NSStackView(views: [innerRow, Self.makeSeparator(), modelLabel, modelSummaryStack])
        vStack.orientation = NSUserInterfaceLayoutOrientation.vertical
        vStack.spacing = 8
        vStack.edgeInsets = NSEdgeInsets(top: Self.cardPadding, left: Self.cardPadding,
                                         bottom: Self.cardPadding, right: Self.cardPadding)
        summaryCard.addSubview(vStack)
        vStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: summaryCard.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor)
        ])
        contentStack.addArrangedSubview(summaryCard)

        // ──────── 逐时消耗卡片 ────────
        contentStack.addArrangedSubview(Self.sectionTitle("逐时消耗"))
        let hourlyCard = Self.makeCard()
        hourlyChartHosting.translatesAutoresizingMaskIntoConstraints = false
        hourlyCard.addSubview(hourlyChartHosting)
        NSLayoutConstraint.activate([
            hourlyChartHosting.topAnchor.constraint(equalTo: hourlyCard.topAnchor, constant: 8),
            hourlyChartHosting.leadingAnchor.constraint(equalTo: hourlyCard.leadingAnchor, constant: 8),
            hourlyChartHosting.trailingAnchor.constraint(equalTo: hourlyCard.trailingAnchor, constant: -8),
            hourlyChartHosting.bottomAnchor.constraint(equalTo: hourlyCard.bottomAnchor, constant: -8)
        ])
        contentStack.addArrangedSubview(hourlyCard)

        // ──────── 近 7 日卡片 ────────
        contentStack.addArrangedSubview(Self.sectionTitle("近 7 日"))
        let historyCard = Self.makeCard()
        historyChartHosting.translatesAutoresizingMaskIntoConstraints = false
        historyCard.addSubview(historyChartHosting)
        NSLayoutConstraint.activate([
            historyChartHosting.topAnchor.constraint(equalTo: historyCard.topAnchor, constant: 8),
            historyChartHosting.leadingAnchor.constraint(equalTo: historyCard.leadingAnchor, constant: 8),
            historyChartHosting.trailingAnchor.constraint(equalTo: historyCard.trailingAnchor, constant: -8),
            historyChartHosting.bottomAnchor.constraint(equalTo: historyCard.bottomAnchor, constant: -8)
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

    private static func sectionTitle(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = Self.titleFont
        l.textColor = .labelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private static func makeCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = Self.cornerRadius
        v.layer?.backgroundColor = Self.cardBg.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private static func makeSeparator() -> NSView {
        let l = NSView()
        l.wantsLayer = true
        l.layer?.backgroundColor = NSColor.separatorColor.cgColor
        l.translatesAutoresizingMaskIntoConstraints = false
        l.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return l
    }

    private static func makeBigNumber(icon: String, label: String,
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
        titleLabel.textColor = NSColor.secondaryLabelColor

        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        textField.textColor = color
        textField.alignment = NSTextAlignment.center

        let vStack = NSStackView(views: [iconView, titleLabel, textField])
        vStack.orientation = NSUserInterfaceLayoutOrientation.vertical
        vStack.spacing = 2
        vStack.alignment = NSLayoutConstraint.Attribute.centerX
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

    private func makeModelRow(_ mu: TokenUsageByModel) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: shortModelName(mu.model))
        nameLabel.font = Self.bodyFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        let tokensLabel = NSTextField(labelWithString: Self.formatTokens(mu.totalTokens))
        tokensLabel.font = Self.numberFont
        tokensLabel.textColor = NSColor.systemBlue
        tokensLabel.alignment = NSTextAlignment.right

        let costLabel = NSTextField(labelWithString: Self.formatCost(mu.cost))
        costLabel.font = Self.numberFont
        costLabel.textColor = NSColor.systemOrange
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

    // MARK: - 格式化

    private static func formatTokens(_ count: Int) -> String {
        if count >= 100_000_000 { return String(format: "%.1f亿", Double(count) / 100_000_000) }
        if count >= 10_000 { return String(format: "%.1f万", Double(count) / 10_000) }
        return "\(count)"
    }

    private static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return String(format: "¥%.4f", cost) }
        if cost < 1 { return String(format: "¥%.3f", cost) }
        return String(format: "¥%.2f", cost)
    }

    private func shortModelName(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("gpt-4o") { return "GPT-4o" }
        if m.contains("gpt-4") { return "GPT-4" }
        if m.contains("claude-3.5") || m.contains("claude-35") { return "Claude 3.5" }
        if m.contains("claude") { return "Claude" }
        if m.contains("gemini") { return "Gemini" }
        if m.contains("deepseek") { return "DeepSeek" }
        if model.count > 12 { return String(model.prefix(10)) + "…" }
        return model
    }
}
