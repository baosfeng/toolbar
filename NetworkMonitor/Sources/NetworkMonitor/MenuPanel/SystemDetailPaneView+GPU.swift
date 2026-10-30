import AppKit
import NetworkMonitorCore

// MARK: - GPU 详情页

/// GPU 详情 — 活跃利用率（28pt）+ 60 秒 0–10% 量程曲线 + 显存已用 + 状态
///
/// 量程固定 0–10%：本机 GPU 大多在 0–2% 之间波动，自适应纵轴会把 0.4% 的抖动画成满画布，
/// 读起来像「GPU 在忙」；固定量程下「几乎贴底」才是真实状态。
final class SystemGPUDetailView: NSView {

    private let hero = SystemMetricValueView(fontSize: 28, unitFontSize: 10)
    private let subtitle: NSTextField
    private let chartCard: SystemDetailCardView
    private let area = SystemAreaChartView(height: 46)
    private let factsCard: SystemDetailCardView
    private let facts = SystemDetailFactGrid(rows: 4)
    private let note = SystemDetailNoteView()

    init() {
        let wash = SystemPalette.wash(.gpu)
        subtitle = MenuPanelLabel.text("活跃利用率 · IOAccelerator PerformanceStatistics · Device Utilization",
                                       font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                       color: SystemPalette.meta)
        chartCard = SystemDetailCardView(title: "近 60 秒", meta: "0–10%", wash: wash)
        factsCard = SystemDetailCardView(wash: wash)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        area.lineColor = SystemPalette.gpu
        area.fixedMaximum = 0.10
        chartCard.addContent(area)
        factsCard.addContent(facts)
        factsCard.addContent(note)
        note.update("显存总量与 GPU 核数本机取不到（IOAccelerator 无对应字段），"
            + "故只显示已用显存、不给占比条。")

        let stack = NSStackView(views: [hero, subtitle, chartCard, factsCard])
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
        for view in [chartCard, factsCard] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("GPU 详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 刷新
    func update(_ context: SystemDetailContext) {
        guard let gpu = context.snapshot?.gpu else {
            hero.reset(color: SystemPalette.meta)
            area.values = []
            facts.update(unavailableFacts(sample: context.sampleInterval),
                         keyColor: SystemPalette.gpuInk)
            return
        }
        hero.update(value: SystemDetailFormatting.percentNumberText(gpu.utilization),
                    color: SystemPalette.gpuInk, unit: "%")
        area.values = context.gpuHistory

        let memory = SystemDetailFormatting.byteCountParts(gpu.memoryUsed.map(Double.init))
        let sample = SystemDetailPaneView.sampleIntervalParts(context.sampleInterval)
        facts.update([
            .init(label: "已用显存", value: memory.value, unit: memory.unit, isKey: true),
            .init(label: "GPU 核数", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "当前", value: SystemDetailFormatting.gpuStateText(utilization: gpu.utilization),
                  unit: nil, isKey: false),
            .init(label: "采样", value: sample.value, unit: sample.unit, isKey: false),
        ], keyColor: SystemPalette.gpuInk)
    }

    /// 空态事实行（逐项「—」，不留空行）
    private func unavailableFacts(sample: Double?) -> [SystemDetailFactGrid.Item] {
        let sampleParts = SystemDetailPaneView.sampleIntervalParts(sample)
        return [
            .init(label: "已用显存", value: SystemPaneFormat.placeholder, unit: nil, isKey: true),
            .init(label: "GPU 核数", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "当前", value: SystemPaneFormat.placeholder, unit: nil, isKey: false),
            .init(label: "采样", value: sampleParts.value, unit: sampleParts.unit, isKey: false),
        ]
    }
}
