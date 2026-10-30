import AppKit
import NetworkMonitorCore

// MARK: - 压力 / 进程详情页

/// 压力详情 — 负载三线（1/5/15 分钟 + 核数参考虚线）+ 进程 Top-10 与「CPU 榜 / 内存榜」切换
///
/// 这是「压力卡」的二级页：首屏只放 Top-2 与「全部 ›」，进程全量榜与内存榜都收在这里。
/// 榜单排序沿用采样层已算好的两份 Top-N（不在这里二次排序），条形刻度走 Core 的
/// `SystemProcessBoard`，与首屏同一套口径。
final class SystemProcessDetailView: NSView {

    private let loadCard: SystemDetailCardView
    private let loadChart = SystemLoadChartView(height: 46)
    private let processCard: SystemDetailCardView
    private let processList = SystemProcessListView(rows: 10)
    private let note = SystemDetailNoteView()
    private let metricToggle = NSStackView()
    private let cpuButton = NSButton(title: SystemProcessMetric.cpu.title, target: nil, action: nil)
    private let memoryButton = NSButton(title: SystemProcessMetric.memory.title, target: nil, action: nil)
    private var metric: SystemProcessMetric = .cpu
    private var lastContext: SystemDetailContext?

    init() {
        let wash = SystemPalette.wash(.load)
        loadCard = SystemDetailCardView(title: "负载三线", meta: "", wash: wash)
        processCard = SystemDetailCardView(title: "进程 Top-10", wash: wash, accessory: metricToggle)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        loadCard.addContent(loadChart)
        configureToggle()
        processCard.addContent(processList)
        processCard.addContent(note)

        let stack = NSStackView(views: [loadCard, processCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in [loadCard, processCard] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("压力详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: 榜单切换

    private func configureToggle() {
        metricToggle.orientation = .horizontal
        metricToggle.alignment = .centerY
        metricToggle.spacing = 2
        for button in [cpuButton, memoryButton] {
            button.isBordered = false
            button.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
            button.setButtonType(.momentaryChange)
            button.target = self
            button.action = #selector(switchMetric(_:))
            button.toolTip = SystemPaneTip.processToggle
            metricToggle.addArrangedSubview(button)
        }
        applyToggleStyle()
    }

    /// 当前维度高亮（原型「切」的能力搬到这里：两个榜都要能到）
    private func applyToggleStyle() {
        cpuButton.contentTintColor = metric == .cpu ? SystemPalette.loadInk : SystemPalette.meta
        memoryButton.contentTintColor = metric == .memory ? SystemPalette.loadInk : SystemPalette.meta
        cpuButton.toolTip = SystemPaneTip.processMetric(.cpu)
        memoryButton.toolTip = SystemPaneTip.processMetric(.memory)
    }

    @objc private func switchMetric(_ sender: NSButton) {
        metric = sender === memoryButton ? .memory : .cpu
        applyToggleStyle()
        if let lastContext {
            renderProcesses(lastContext)
        }
    }

    // MARK: 数据刷新

    func update(_ context: SystemDetailContext) {
        lastContext = context
        let load = context.snapshot?.load
        loadChart.coreCount = max(0, load?.coreCount ?? 0)
        loadChart.shortValues = context.loadShortHistory
        loadChart.mediumValues = context.loadMediumHistory
        loadChart.longValues = context.loadLongHistory
        let peak = (context.loadShortHistory + context.loadMediumHistory
            + context.loadLongHistory).max() ?? 0
        loadChart.axisMaximum = SystemLoadChartView.axisMaximum(coreCount: loadChart.coreCount,
                                                                peak: peak)
        loadCard.updateMeta(load.map { "/\(max(0, $0.coreCount))" } ?? SystemPaneFormat.placeholder)
        renderProcesses(context)
    }

    private func renderProcesses(_ context: SystemDetailContext) {
        let snapshot = context.snapshot?.processes
        let rows = SystemPaneView.processRows(snapshot, metric: metric, limit: 10,
                                              memoryTotal: context.snapshot?.memory?.total)
        if rows.isEmpty {
            processList.update([], unavailableTip: SystemPaneTip.processUnavailable)
        } else {
            processList.update(rows, unavailableTip: SystemPaneTip.processUnavailable)
        }
        let sample = SystemDetailFormatting.sampleIntervalText(context.sampleInterval)
        let sampleText = sample == SystemDetailFormatting.placeholder ? "采样周期不可得" : sample + "采样"
        // 不可得时写明原因，不写「本帧扫描 0 个进程」——那会被读成「真的没有进程」
        let scanText = snapshot.map { "本帧扫描 \($0.scannedCount) 个进程" }
            ?? "进程读数不可得（首帧差分需要两个采样点，或 proc_pidinfo 全部返回 -1）"
        note.update(sampleText + " · 进程榜取 proc_pidinfo 全量遍历（\(scanText)）"
            + " · CPU% 为采样间隔差分，单进程可 >100%（多线程合法）")
    }
}
