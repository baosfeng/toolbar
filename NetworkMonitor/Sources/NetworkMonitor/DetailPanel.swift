import AppKit
import NetworkMonitorCore

// MARK: - Detail Panel

/// 浮动详情面板 — macOS 15 现代毛玻璃风格
///
/// 布局：卡片分区（网速 → 网络信息 → 电池 → 活跃进程）
/// 材质：NSVisualEffectView（.popover 毛玻璃）
@MainActor
final class DetailPanel: NSPanel {
    // MARK: - 网速
    private let downSpeedLabel = NSTextField(labelWithString: "0 KB/s")
    private let upSpeedLabel = NSTextField(labelWithString: "0 KB/s")

    // MARK: - 网络信息
    private let ipLabel = NSTextField(labelWithString: "—")
    private let wifiLabel = NSTextField(labelWithString: "—")
    /// 今日流量
    private let todayLabel = NSTextField(labelWithString: "今日  ↓0 B  ↑0 B")
    /// 近7日逐日列表（多行）
    private let weekListLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        l.textColor = .secondaryLabelColor
        l.isBezeled = false
        l.isEditable = false
        l.drawsBackground = false
        return l
    }()

    // MARK: - 电池
    private let batteryIconView = NSImageView()
    private let batteryPercentLabel = NSTextField(labelWithString: "—%")
    private let batteryTimeLabel = NSTextField(labelWithString: "")
    private let batteryStatusLabel = NSTextField(labelWithString: "")
    private let batteryHealthLabel = NSTextField(labelWithString: "")
    private let batteryCycleLabel = NSTextField(labelWithString: "")

    // MARK: - 进程
    private let processList = NSTextField(labelWithString: "")

    // MARK: - 字体常量
    private let bigFont = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
    private let normalFont = NSFont.systemFont(ofSize: 12)
    private let smallFont = NSFont.systemFont(ofSize: 11)
    private let captionFont = NSFont.systemFont(ofSize: 10)
    private let tinyFont = NSFont.systemFont(ofSize: 9)

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "网络监控"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false

        setupViews()
    }

    // MARK: - 布局

    private func setupViews() {
        guard let content = contentView else { return }

        // ── 毛玻璃背景 ──
        let vibrancy = NSVisualEffectView()
        vibrancy.material = .popover
        vibrancy.state = .active
        vibrancy.blendingMode = .behindWindow
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(vibrancy, positioned: .below, relativeTo: nil)

        // ── 内容容器 ──
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)

        // ═══ 卡片 1：网速 ═══
        let speedCard = makeCard()
        container.addSubview(speedCard)
        setupSpeedSection(speedCard)

        // ═══ 卡片 2：网络信息 ═══
        let infoCard = makeCard()
        container.addSubview(infoCard)
        setupInfoSection(infoCard)

        // ═══ 卡片 3：电池 ═══
        let batteryCard = makeCard()
        container.addSubview(batteryCard)
        setupBatterySection(batteryCard)

        // ═══ 卡片 4：活跃进程 ═══
        let processCard = makeCard()
        container.addSubview(processCard)
        setupProcessSection(processCard)

        // ═══ 约束 ═══
        let edge: CGFloat = 16
        let cardSpacing: CGFloat = 8

        NSLayoutConstraint.activate([
            vibrancy.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            vibrancy.topAnchor.constraint(equalTo: content.topAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            container.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: edge),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -edge),
            container.topAnchor.constraint(equalTo: content.topAnchor, constant: edge),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -edge),

            // 网速卡片
            speedCard.topAnchor.constraint(equalTo: container.topAnchor),
            speedCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            speedCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // 网络信息卡片
            infoCard.topAnchor.constraint(equalTo: speedCard.bottomAnchor, constant: cardSpacing),
            infoCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            infoCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // 电池卡片
            batteryCard.topAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: cardSpacing),
            batteryCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            batteryCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // 进程卡片
            processCard.topAnchor.constraint(equalTo: batteryCard.bottomAnchor, constant: cardSpacing),
            processCard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            processCard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            processCard.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - 卡片工厂

    private func makeCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func styleCardBackground(_ card: NSView) {
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
    }

    // MARK: - 网速分区

    private func setupSpeedSection(_ card: NSView) {
        styleCardBackground(card)

        // 分隔左右：下行 / 上行
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // ── 下行 ──
        let downStack = NSStackView()
        downStack.orientation = .vertical
        downStack.alignment = .centerX
        downStack.spacing = 2

        let downIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "下行") {
            downIcon.image = img
            downIcon.contentTintColor = .systemGreen
            downIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        }
        downIcon.translatesAutoresizingMaskIntoConstraints = false
        downIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        downIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        downSpeedLabel.font = bigFont
        downSpeedLabel.textColor = .systemGreen
        downSpeedLabel.alignment = .center
        downSpeedLabel.isBezeled = false
        downSpeedLabel.isEditable = false
        downSpeedLabel.drawsBackground = false

        downStack.addArrangedSubview(downIcon)
        downStack.addArrangedSubview(downSpeedLabel)
        stack.addArrangedSubview(downStack)

        // ── 分隔线 ──
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(divider)

        // ── 上行 ──
        let upStack = NSStackView()
        upStack.orientation = .vertical
        upStack.alignment = .centerX
        upStack.spacing = 2

        let upIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "上行") {
            upIcon.image = img
            upIcon.contentTintColor = .systemOrange
            upIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        }
        upIcon.translatesAutoresizingMaskIntoConstraints = false
        upIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        upIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        upSpeedLabel.font = bigFont
        upSpeedLabel.textColor = .systemOrange
        upSpeedLabel.alignment = .center
        upSpeedLabel.isBezeled = false
        upSpeedLabel.isEditable = false
        upSpeedLabel.drawsBackground = false

        upStack.addArrangedSubview(upIcon)
        upStack.addArrangedSubview(upSpeedLabel)
        stack.addArrangedSubview(upStack)

        let cardPadding: CGFloat = 16

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: cardPadding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cardPadding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cardPadding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -cardPadding),

            divider.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            divider.topAnchor.constraint(equalTo: card.topAnchor, constant: cardPadding + 8),
            divider.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -cardPadding - 8),
            divider.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - 网络信息分区

    private func setupInfoSection(_ card: NSView) {
        styleCardBackground(card)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let ipRow = makeInfoRow(symbol: "network", tint: .systemBlue, label: ipLabel)
        let wifiRow = makeInfoRow(symbol: "wifi", tint: .systemBlue, label: wifiLabel)
        let todayRow = makeInfoRow(symbol: "sun.max", tint: .systemOrange, label: todayLabel)

        stack.addArrangedSubview(ipRow)
        stack.addArrangedSubview(wifiRow)
        stack.addArrangedSubview(todayRow)
        stack.addArrangedSubview(weekListLabel)

        let cardPadding: CGFloat = 12
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: cardPadding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cardPadding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cardPadding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -cardPadding),
        ])
    }

    // MARK: - 电池分区

    private func setupBatterySection(_ card: NSView) {
        styleCardBackground(card)

        // 左侧：大电池图标
        batteryIconView.translatesAutoresizingMaskIntoConstraints = false
        let battConfig = NSImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        if let img = NSImage(systemSymbolName: "battery.100", accessibilityDescription: "电池") {
            batteryIconView.image = img
            batteryIconView.contentTintColor = .systemGreen
            batteryIconView.symbolConfiguration = battConfig
        }
        card.addSubview(batteryIconView)

        // 右侧信息栈
        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.spacing = 2
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(infoStack)

        batteryPercentLabel.font = bigFont
        batteryPercentLabel.textColor = .labelColor
        batteryPercentLabel.alignment = .left
        batteryPercentLabel.isBezeled = false
        batteryPercentLabel.isEditable = false
        batteryPercentLabel.drawsBackground = false

        batteryTimeLabel.font = normalFont
        batteryTimeLabel.textColor = .secondaryLabelColor
        batteryTimeLabel.alignment = .left
        batteryTimeLabel.isBezeled = false
        batteryTimeLabel.isEditable = false
        batteryTimeLabel.drawsBackground = false

        batteryStatusLabel.font = tinyFont
        batteryStatusLabel.textColor = .secondaryLabelColor
        batteryStatusLabel.alignment = .left
        batteryStatusLabel.isBezeled = false
        batteryStatusLabel.isEditable = false
        batteryStatusLabel.drawsBackground = false

        batteryCycleLabel.font = tinyFont
        batteryCycleLabel.textColor = .secondaryLabelColor
        batteryCycleLabel.alignment = .left
        batteryCycleLabel.isBezeled = false
        batteryCycleLabel.isEditable = false
        batteryCycleLabel.drawsBackground = false

        batteryHealthLabel.font = tinyFont
        batteryHealthLabel.textColor = .secondaryLabelColor
        batteryHealthLabel.alignment = .left
        batteryHealthLabel.isBezeled = false
        batteryHealthLabel.isEditable = false
        batteryHealthLabel.drawsBackground = false

        infoStack.addArrangedSubview(batteryPercentLabel)
        infoStack.addArrangedSubview(batteryTimeLabel)
        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 12
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.addArrangedSubview(makeSymbolRow(symbol: "arrow.counterclockwise", tint: .secondaryLabelColor, label: batteryCycleLabel))
        bottomRow.addArrangedSubview(makeSymbolRow(symbol: "heart.fill", tint: .systemRed, label: batteryHealthLabel))
        infoStack.addArrangedSubview(batteryStatusLabel)
        infoStack.addArrangedSubview(bottomRow)

        let cardPadding: CGFloat = 12
        NSLayoutConstraint.activate([
            batteryIconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cardPadding),
            batteryIconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            batteryIconView.widthAnchor.constraint(equalToConstant: 40),
            batteryIconView.heightAnchor.constraint(equalToConstant: 40),

            infoStack.leadingAnchor.constraint(equalTo: batteryIconView.trailingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cardPadding),
            infoStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    // MARK: - 进程分区

    private func setupProcessSection(_ card: NSView) {
        styleCardBackground(card)

        let headerLabel = NSTextField(labelWithString: "活跃进程")
        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.isBezeled = false
        headerLabel.isEditable = false
        headerLabel.drawsBackground = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(headerLabel)

        processList.font = smallFont
        processList.textColor = .labelColor
        processList.isBezeled = false
        processList.isEditable = false
        processList.drawsBackground = false
        processList.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(processList)

        let cardPadding: CGFloat = 12
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: cardPadding),
            headerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cardPadding),
            headerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cardPadding),

            processList.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            processList.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: cardPadding),
            processList.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -cardPadding),
            processList.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -cardPadding),
        ])
    }

    // MARK: - 辅助方法

    /// 创建带 SF Symbol 图标的信息行
    private func makeInfoRow(symbol: String, tint: NSColor, label: NSTextField) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iv.image = img
            iv.contentTintColor = tint
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        }
        iv.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 18).isActive = true
        row.addSubview(iv)

        label.font = normalFont
        label.textColor = .labelColor
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iv.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 22),
        ])
        return row
    }

    /// 创建带 SF Symbol 的紧凑行（用于电池底部）
    private func makeSymbolRow(symbol: String, tint: NSColor, label: NSTextField) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iv.image = img
            iv.contentTintColor = tint
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        }
        iv.widthAnchor.constraint(equalToConstant: 12).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 12).isActive = true
        row.addSubview(iv)

        label.font = tinyFont
        label.textColor = .secondaryLabelColor
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iv.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 16),
        ])
        return row
    }

    // MARK: - 数据更新

    func update(battery: BatteryStatus, downSpeed: Double, upSpeed: Double,
                totalRx: UInt64, totalTx: UInt64,
                todayRx: UInt64, todayTx: UInt64,
                weekDetail: String,
                ip: String?, wifi: String, processes: [ProcessNetUsage])
    {
        // 网速
        downSpeedLabel.stringValue = formatSpeedShort(downSpeed) + "/s"
        upSpeedLabel.stringValue = formatSpeedShort(upSpeed) + "/s"

        // 网络信息
        ipLabel.stringValue = ip ?? "未连接"
        wifiLabel.stringValue = "Wi-Fi: \(wifi)"
        todayLabel.stringValue = "今日  ↓\(formatBytesFull(todayRx))  ↑\(formatBytesFull(todayTx))"
        weekListLabel.stringValue = weekDetail

        // 电池
        batteryPercentLabel.stringValue = "\(battery.percentage)%"
        batteryTimeLabel.stringValue = battery.timeLabel

        let src = battery.powerSource == "AC Power" ? "交流电" : "电池"
        let charging = battery.isCharging ? "⚡ 充电中" : battery.isCharged ? "✓ 已充满" : ""
        batteryStatusLabel.stringValue = "\(src)  \(charging)"

        batteryCycleLabel.stringValue = "\(battery.cycleCount) 次"
        batteryHealthLabel.stringValue = battery.health

        // 电池图标颜色
        let battColor: NSColor
        if battery.percentage <= 20 {
            battColor = .systemRed
        } else if battery.isCharging || battery.isCharged {
            battColor = .systemGreen
        } else {
            battColor = .labelColor
        }
        batteryIconView.contentTintColor = battColor

        // 电池图标
        let battName: String
        if battery.isCharging {
            battName = "battery.100.bolt"
        } else if battery.isCharged {
            battName = "battery.100"
        } else if battery.percentage > 75 {
            battName = "battery.75"
        } else if battery.percentage > 50 {
            battName = "battery.50"
        } else if battery.percentage > 25 {
            battName = "battery.25"
        } else {
            battName = "battery.25"
        }
        if let img = NSImage(systemSymbolName: battName, accessibilityDescription: "电池") {
            batteryIconView.image = img
        }

        // 进程列表
        let top = processes.prefix(8)
        if top.isEmpty {
            processList.stringValue = "暂无活跃流量"
            processList.textColor = .secondaryLabelColor
        } else {
            processList.stringValue = top.map { proc in
                let down = formatSpeedShort(Double(proc.bytesIn))
                let up = formatSpeedShort(Double(proc.bytesOut))
                let name = proc.name.count > 16 ? String(proc.name.prefix(15)) + "…" : proc.name
                return "\(name)  ↓\(down)/s  ↑\(up)/s"
            }.joined(separator: "\n")
            processList.textColor = .labelColor
        }
    }
}
