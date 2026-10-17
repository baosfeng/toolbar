import AppKit
import NetworkMonitorCore

// MARK: - 网络页

/// 网络页 — 实时速率（大数字 + 折线）、今日流量（占比轨道）、活跃进程 Top5、近 6 日柱状图
final class NetworkPaneView: MenuPanelPaneView {

    // MARK: 实时速率

    private let downValueLabel = MenuPanelLabel.text("0", font: MenuPanelStyle.heroFont, color: MenuPanelStyle.downColor)
    private let downUnitLabel = MenuPanelLabel.text("B/s", font: MenuPanelStyle.heroUnitFont,
                                                    color: MenuPanelStyle.secondaryText)
    private let upValueLabel = MenuPanelLabel.text("0", font: MenuPanelStyle.sideValueFont, color: MenuPanelStyle.upColor)
    private let upUnitLabel = MenuPanelLabel.text("B/s", font: MenuPanelStyle.heroUnitFont,
                                                  color: MenuPanelStyle.secondaryText)
    private let downSparkline = MenuPanelSparklineView(lineColor: MenuPanelStyle.downColor)
    private let upSparkline = MenuPanelSparklineView(lineColor: MenuPanelStyle.upColor)

    // MARK: 今日流量

    private let todayDownLabel = MenuPanelLabel.value("—", color: MenuPanelStyle.downColor)
    private let todayUpLabel = MenuPanelLabel.value("—", color: MenuPanelStyle.upColor)
    private let todayDownShareLabel = MenuPanelLabel.text("", font: MenuPanelStyle.smallValueFont,
                                                          color: MenuPanelStyle.tertiaryText)
    private let todayUpShareLabel = MenuPanelLabel.text("", font: MenuPanelStyle.smallValueFont,
                                                        color: MenuPanelStyle.tertiaryText)
    private let downTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.downColor)
    private let upTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.upColor)

    // MARK: 活跃进程 / 图表

    private let processHeader = MenuPanelHeaderRow(title: "活跃进程", trailing: "0 个")
    private let processStack = NSStackView()
    private let processEmptyLabel: NSTextField = {
        let label = MenuPanelLabel.text("当前没有进程在使用网络",
                                        font: NSFont.systemFont(ofSize: 12, weight: .regular),
                                        color: .labelColor)
        label.alignment = .left
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()
    private let chartHeader = MenuPanelHeaderRow(title: "近 6 日下行")
    private let barsView = MenuPanelBarsView()

    /// 进程行签名 — 内容未变化时跳过重建，避免每 5 秒重建视图
    private var processSignature = ""

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：临时抬高进程行上限，用来构造「内容高于 520pt」的场景；
    /// 发布路径固定 Top5（`MenuPanelMetrics.topProcesses(..., limit: 5)`）。
    var processRowLimitOverride: Int?
#endif

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        stack.addArrangedSubview(makeHeroRow())
        stack.addArrangedSubview(makeTodayBox())
        stack.addArrangedSubview(makeProcessSection())
        let chartSection = makeChartSection()
        stack.addArrangedSubview(chartSection)

        // 分区宽度撑满面板内容区
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 子区块构建

    /// 速率区：左侧大数字（下行）+ 右侧次数字（上行），各带一条折线
    private func makeHeroRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let downColumn = NSStackView()
        downColumn.orientation = .vertical
        downColumn.alignment = .leading
        downColumn.spacing = 2

        downColumn.addArrangedSubview(MenuPanelLabel.section("实时下行"))
        let downValueRow = NSStackView()
        downValueRow.orientation = .horizontal
        downValueRow.alignment = .lastBaseline
        downValueRow.spacing = 2
        downValueRow.addArrangedSubview(downValueLabel)
        downValueRow.addArrangedSubview(downUnitLabel)
        downColumn.addArrangedSubview(downValueRow)
        downColumn.addArrangedSubview(downSparkline)

        let upColumn = NSStackView()
        upColumn.orientation = .vertical
        upColumn.alignment = .trailing
        upColumn.spacing = 2
        let upTitle = MenuPanelLabel.section("上行")
        upColumn.addArrangedSubview(upTitle)
        let upValueRow = NSStackView()
        upValueRow.orientation = .horizontal
        upValueRow.alignment = .lastBaseline
        upValueRow.spacing = 2
        upValueRow.addArrangedSubview(upValueLabel)
        upValueRow.addArrangedSubview(upUnitLabel)
        upColumn.addArrangedSubview(upValueRow)
        upColumn.addArrangedSubview(upSparkline)

        let row = NSStackView(views: [downColumn, MenuPanelLabel.spacer(), upColumn])
        row.orientation = .horizontal
        row.alignment = .bottom
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// 今日流量卡片：两行数值 + 两条占比轨道
    private func makeTodayBox() -> NSView {
        let box = MenuPanelCardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])

        stack.addArrangedSubview(makeTodayRow(title: "今日下行", value: todayDownLabel, share: todayDownShareLabel))
        stack.addArrangedSubview(downTrack)
        stack.addArrangedSubview(makeTodayRow(title: "今日上行", value: todayUpLabel, share: todayUpShareLabel))
        stack.addArrangedSubview(upTrack)
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return box
    }

    /// 今日流量单行：标题 + 数值 + 占比说明
    private func makeTodayRow(title: String, value: NSTextField, share: NSTextField) -> NSView {
        let row = NSStackView(views: [MenuPanelLabel.text(title, font: MenuPanelStyle.sectionFont,
                                                          color: MenuPanelStyle.secondaryText),
                                      value,
                                      MenuPanelLabel.spacer(),
                                      share])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    /// 活跃进程区：表头 + Top5 列表 + 空态
    private func makeProcessSection() -> NSView {
        processStack.orientation = .vertical
        processStack.alignment = .leading
        processStack.spacing = 0
        processEmptyLabel.isHidden = false
        // 空态统一 12pt regular + 18pt 行高（此前被 NSStackView 拉伸显得偏大）
        processEmptyLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let section = NSStackView(views: [processHeader, processStack, processEmptyLabel])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4
        for subview in section.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    /// 近 6 日柱状图区
    private func makeChartSection() -> NSView {
        let section = NSStackView(views: [chartHeader, barsView])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        for subview in section.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
    }

    // MARK: - 数据更新

    /// 更新实时速率与大数字（1 秒一次）
    func updateSpeeds(down: Double, up: Double, downHistory: [Double], upHistory: [Double]) {
        let downParts = MenuPanelMetrics.speedParts(down)
        downValueLabel.stringValue = downParts.value
        downUnitLabel.stringValue = downParts.unit
        let upParts = MenuPanelMetrics.speedParts(up)
        upValueLabel.stringValue = upParts.value
        upUnitLabel.stringValue = upParts.unit
        downSparkline.values = downHistory
        upSparkline.values = upHistory
    }

    /// 更新今日流量与近 6 日柱状图（5 秒一次）
    func updateTraffic(todayRx: UInt64, todayTx: UInt64, dailyBars: [MenuPanelMetrics.DailyTrafficBar]) {
        todayDownLabel.stringValue = "↓" + formatBytesFull(todayRx)
        todayUpLabel.stringValue = "↑" + formatBytesFull(todayTx)

        let downShare = MenuPanelMetrics.downShare(rx: todayRx, tx: todayTx)
        let upShare = todayRx + todayTx > 0 ? 1 - downShare : 0
        downTrack.fraction = downShare
        upTrack.fraction = upShare
        todayDownShareLabel.stringValue = "占今日总量 \(Int((downShare * 100).rounded()))%"
        todayUpShareLabel.stringValue = "占今日总量 \(Int((upShare * 100).rounded()))%"

        barsView.bars = dailyBars.map { bar in
            MenuPanelBarsView.Bar(label: bar.label,
                                  value: bar.rx,
                                  valueText: shortBytes(bar.rx),
                                  isToday: bar.isToday)
        }
        if let first = dailyBars.first, let last = dailyBars.last {
            chartHeader.updateTrailing(first.label == last.label
                                       ? first.label
                                       : "\(first.label) — \(last.label) · 下行")
        } else {
            chartHeader.updateTrailing("暂无历史")
        }
    }

    /// 更新活跃进程 Top5（5 秒一次）
    func updateProcesses(_ processes: [ProcessNetUsage]) {
#if DEBUG
        let limit = processRowLimitOverride ?? 5
#else
        let limit = 5
#endif
        let top = MenuPanelMetrics.topProcesses(processes, limit: limit)
        processHeader.updateTrailing("\(top.count) 个")

        // 内容签名：名称 + 速率未变时不重建视图
        let signature = top.map { "\($0.name):\($0.bytesIn):\($0.bytesOut)" }.joined(separator: ",")
        guard signature != processSignature else { return }
        processSignature = signature

        for view in processStack.arrangedSubviews {
            processStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        processEmptyLabel.isHidden = !top.isEmpty
        for process in top {
            let row = MenuPanelProcessRow(process: process)
            processStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: processStack.widthAnchor).isActive = true
        }
    }

    /// 图表数值文案（GB/MB 自适应，数字短，不占宽）
    private func shortBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fG", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.0fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", value / 1_000)
        default:
            return "\(bytes)"
        }
    }
}

// MARK: - 进程行

/// 活跃进程行 — 真实 App 图标（`NSWorkspace.icon(forFile:)`）+ 进程名 + 上下行速率
final class MenuPanelProcessRow: MenuPanelRow {
    private let iconView = NSImageView()

    init(process: ProcessNetUsage) {
        super.init(height: MenuPanelStyle.compactRowHeight, onClick: nil)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.image = AppIconProvider.icon(forProcess: process.name, size: 20)
            ?? AppIconProvider.placeholderIcon(size: 20)
        iconView.contentTintColor = MenuPanelStyle.tertiaryText
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])
        contentStack.addArrangedSubview(iconView)

        contentStack.addArrangedSubview(MenuPanelLabel.text(process.name, font: MenuPanelStyle.bodyFont))
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())

        let downText = "↓" + formatSpeedShort(Double(process.bytesIn))
        let upText = "↑" + formatSpeedShort(Double(process.bytesOut))
        let speeds = MenuPanelLabel.text("\(downText)  \(upText)", font: MenuPanelStyle.smallValueFont,
                                        color: MenuPanelStyle.secondaryText)
        speeds.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(speeds)
    }
}
