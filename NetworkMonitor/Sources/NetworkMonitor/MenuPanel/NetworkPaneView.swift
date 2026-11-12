import AppKit
import NetworkMonitorCore

// MARK: - 网络页

/// 网络页 — 实时速率（大数字 + 折线）、今日流量（占比轨道）、活跃进程 Top5、近 6 日柱状图
final class NetworkPaneView: MenuPanelPaneView {

    // MARK: 实时速率

    let downValueLabel = MenuPanelLabel.text("0", font: MenuPanelStyle.heroFont, color: MenuPanelStyle.downColor)
    let downUnitLabel = MenuPanelLabel.text("B/s", font: MenuPanelStyle.heroUnitFont,
                                                    color: MenuPanelStyle.secondaryText)
    let upValueLabel = MenuPanelLabel.text("0", font: MenuPanelStyle.sideValueFont, color: MenuPanelStyle.upColor)
    let upUnitLabel = MenuPanelLabel.text("B/s", font: MenuPanelStyle.heroUnitFont,
                                                  color: MenuPanelStyle.secondaryText)
    let downSparkline = MenuPanelSparklineView(lineColor: MenuPanelStyle.downColor)
    let upSparkline = MenuPanelSparklineView(lineColor: MenuPanelStyle.upColor)

    // MARK: 今日流量

    let todayDownLabel = MenuPanelLabel.value("—", color: MenuPanelStyle.downColor)
    let todayUpLabel = MenuPanelLabel.value("—", color: MenuPanelStyle.upColor)
    let todayDownShareLabel = MenuPanelLabel.text("", font: MenuPanelStyle.smallValueFont,
                                                          color: MenuPanelStyle.tertiaryText)
    let todayUpShareLabel = MenuPanelLabel.text("", font: MenuPanelStyle.smallValueFont,
                                                        color: MenuPanelStyle.tertiaryText)
    let downTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.downColor)
    let upTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.upColor)

    // MARK: 活跃进程 / 图表

    let processHeader = MenuPanelHeaderRow(title: "活跃进程", trailing: "0 个")
    let processStack = NSStackView()
    // 放宽为 internal：区块装配拆到 NetworkPaneView+Sections.swift
    let processEmptyLabel: NSTextField = {
        let label = MenuPanelLabel.text("当前没有进程在使用网络",
                                        font: PaneCardStyle.rowNameFont,
                                        color: PaneCardStyle.primaryText)
        label.alignment = .left
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()
    let chartHeader = MenuPanelHeaderRow(title: "近 6 日下行")
    /// 近 6 日柱状图 — 柱体区 40pt（额度页同款默认 56pt）：
    /// 本页补齐 22pt 页头 + 20pt 状态带后内容区只余约 388pt，柱图必须矮一档
    let barsView = MenuPanelBarsView(barAreaHeight: 40)

    // MARK: 页头 / 页脚（五页统一骨架）

    /// 页头行 — 与额度 / Token / 系统 / 剪贴板 / 传送同一件（22pt，页名 + 口径 + 动作槽）
    let headerView = PaneHeaderRowView(title: "网络")
    /// 页脚状态带 — 与其余四页同壳（20pt，键值横排）
    let stateBand = PaneStateBandView()

    // MARK: Wi-Fi 链路

    /// 链路条 — 今日流量卡下方、活跃进程上方的一条 20pt
    ///
    /// 内部访问级别：`MenuPanelView+DataUpdates` 要把系统快照里的 wifi 喂进来。
    let wifiLinkBar = WiFiLinkBarView()

    /// 链路条与上下区块的间距（主栈默认 10pt；这条按 4pt 收，见 init 里的理由）
    static let wifiLinkSpacing: CGFloat = 4

    /// 进程行签名 — 内容未变化时跳过重建，避免每 5 秒重建视图
    var processSignature = ""
    /// 当前进程条数口径（页脚状态带显示；nil = 尚未取到数据，不显示该项）
    var processCountText: String?
    /// 最近一帧今日流量（进程条数回填时要用来重算状态带总量）
    var lastTodayRx: UInt64 = 0
    var lastTodayTx: UInt64 = 0

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
        // 主栈间距统一到令牌档（原 10pt 是这一页独有的取值，与额度 / Token 的 4pt 对不上）
        stack.spacing = PaneCardStyle.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let todayBox = makeTodayBox()
        // 顶部页头 → 内容 → 页脚状态带：与其余四页同一顺序（此前网络页两头都没有）
        stack.addArrangedSubview(headerView)
        stack.addArrangedSubview(makeHeroRow())
        stack.addArrangedSubview(todayBox)
        // 链路条紧跟今日流量、在活跃进程之前（Lead 定的落点）
        stack.addArrangedSubview(wifiLinkBar)
        stack.addArrangedSubview(makeProcessSection())
        let chartSection = makeChartSection()
        stack.addArrangedSubview(chartSection)
        // 页脚状态带收尾（与其余四页同一落点）
        stack.addArrangedSubview(stateBand)

        // 链路条前后各收一档间距：链路条是「附加口径」不是独立区块，与上下都只留 4pt
        stack.setCustomSpacing(Self.wifiLinkSpacing, after: todayBox)
        stack.setCustomSpacing(Self.wifiLinkSpacing, after: wifiLinkBar)
        // 页脚状态带与图表区之间收一档：20pt 带再叠 4pt 间距已到高度上限
        stack.setCustomSpacing(PaneCardStyle.cardSpacing, after: chartSection)

        // 分区宽度撑满面板内容区
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

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
        // 页脚状态带与本帧流量同源（进程条数回填时复用同一份总量）
        lastTodayRx = todayRx
        lastTodayTx = todayTx
        updateBand(todayRx: todayRx, todayTx: todayTx)

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

    /// 更新 Wi-Fi 链路条（跟随系统指标 5 秒慢节拍，不做独立高频刷新）
    func updateWiFiLink(_ snapshot: WiFiLinkSnapshot?) {
        wifiLinkBar.update(snapshot)
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
        let countText = "\(top.count) 个"
        if processCountText != countText {
            processCountText = countText
            updateBand(todayRx: lastTodayRx, todayTx: lastTodayTx)
        }

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
}
