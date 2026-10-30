import AppKit
import NetworkMonitorCore

// MARK: - CPU 详情页

/// CPU 详情 — 22% 总利用率（28pt）+ 60 秒用户/系统堆叠面积 + 每核热力格 + P/E 与忙闲拆分
///
/// 首屏下沉回这里的三项：每核柱阵、P/E 核数与逐核百分比、忙/闲占比。
/// 所有读数来自同一帧 `CPUSnapshot` 与同一条 60 点历史（不重新采样）。
final class SystemCPUDetailView: NSView {

    private let hero = SystemMetricValueView(fontSize: 28, unitFontSize: 10)
    private let subtitle: NSTextField
    private let splitLegend = SystemUsageSplitView()
    private let chartCard: SystemDetailCardView
    private let area = SystemAreaChartView(height: 46)
    private let coresCard: SystemDetailCardView
    private let heat = SystemDetailHeatGridView()
    private let factsCard: SystemDetailCardView
    private let facts = SystemDetailFactGrid(rows: 4)

    init() {
        let wash = SystemPalette.wash(.cpu)
        subtitle = MenuPanelLabel.text("",
                                       font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                       color: SystemPalette.meta)
        chartCard = SystemDetailCardView(title: "近 60 秒", meta: "用户 / 系统",
                                         wash: wash, accessory: splitLegend)
        coresCard = SystemDetailCardView(title: "每核", wash: wash)
        factsCard = SystemDetailCardView(wash: wash)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        chartCard.addContent(area)
        coresCard.addContent(heat)
        factsCard.addContent(facts)

        let stack = NSStackView(views: [hero, subtitle, chartCard, coresCard, factsCard])
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
        for view in [chartCard, coresCard, factsCard] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("CPU 详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 刷新
    func update(_ context: SystemDetailContext) {
        guard let cpu = context.snapshot?.cpu else {
            hero.reset(color: SystemPalette.meta)
            subtitle.stringValue = "总利用率 · CPU 读数不可得"
            splitLegend.update(total: nil, system: nil)
            area.values = []
            area.overlayValues = []
            heat.cores = []
            coresCard.updateMeta("每核读数不可得")
            facts.update(unavailableFacts(), keyColor: SystemPalette.cpuInk)
            return
        }
        hero.update(value: SystemDetailFormatting.percentNumberText(cpu.totalUsage),
                    color: SystemPalette.cpuInk, unit: "%")
        subtitle.stringValue = "总利用率 · host_processor_info 全核 ticks 差分 · "
            + Self.sampleText(context.sampleInterval)
        splitLegend.update(total: cpu.totalUsage, system: cpu.systemUsage)
        area.values = context.cpuHistory
        area.overlayValues = context.cpuSystemHistory

        let split = SystemMetricsFormatting.splitCores(perCore: cpu.perCore,
                                                       performanceCores: cpu.performanceCores,
                                                       efficiencyCores: cpu.efficiencyCores)
        var cores: [SystemCoreUsage] = split.performance.enumerated().map { index, usage in
            SystemCoreUsage(label: "P\(index)", usage: SystemPaneView.clamp(usage),
                            isPerformance: true)
        }
        cores += split.efficiency.enumerated().map { index, usage in
            SystemCoreUsage(label: "E\(index)", usage: SystemPaneView.clamp(usage),
                            isPerformance: false)
        }
        if cores.isEmpty {
            cores = cpu.perCore.enumerated().map { index, usage in
                SystemCoreUsage(label: "\(index)", usage: SystemPaneView.clamp(usage),
                                isPerformance: true)
            }
        }
        heat.cores = cores
        coresCard.updateMeta("P 核均 \(SystemDetailFormatting.meanCompactPercentText(split.performance))"
            + " · E 核均 \(SystemDetailFormatting.meanCompactPercentText(split.efficiency))")

        let busy = SystemDetailFormatting.percentNumberText(cpu.totalUsage)
        let idle = SystemDetailFormatting.percentNumberText(max(0, 1 - cpu.totalUsage))
        facts.update([
            .init(label: "P 核（性能）", value: "\(cpu.performanceCores)", unit: "个", isKey: false),
            .init(label: "E 核（能效）", value: "\(cpu.efficiencyCores)", unit: "个", isKey: false),
            .init(label: "忙（非空闲）", value: busy, unit: "%", isKey: true),
            .init(label: "空闲", value: idle, unit: "%", isKey: false),
        ], keyColor: SystemPalette.cpuInk)
    }

    /// 空态事实行（不留空行，逐项「—」）
    private func unavailableFacts() -> [SystemDetailFactGrid.Item] {
        [
            .init(label: "P 核（性能）", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "E 核（能效）", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "忙（非空闲）", value: SystemPaneFormat.placeholder, unit: nil, isKey: true),
            .init(label: "空闲", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
        ]
    }

    /// 采样周期文案（不可得时明确写「采样周期不可得」，不留半句）
    private static func sampleText(_ seconds: Double?) -> String {
        let text = SystemDetailFormatting.sampleIntervalText(seconds)
        return text == SystemDetailFormatting.placeholder ? "采样周期不可得" : text + "采样"
    }
}
