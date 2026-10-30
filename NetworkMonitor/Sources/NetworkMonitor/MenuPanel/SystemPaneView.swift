import AppKit
import NetworkMonitorCore

// MARK: - 系统页

/// 系统页 — 顶部 CPU / GPU / 内存三联 + CPU、GPU、内存、磁盘、温度五张卡
///
/// 密度优先：界面只保留数值、单位与 ≤4 字标签；所有口径说明（采样方式、不可用原因）
/// 都写在卡片 `toolTip` 里，不占版面。
/// 刷新：控制器按 midInterval（5 秒）把 `SystemMonitoringService.snapshot` 推给
/// `update(snapshot:)`；曲线历史由 `updateHistory` / `updateHistories` 注入。
/// 空态：snapshot 整体或任一子项为 nil 时逐卡显示「—」，不隐藏整卡、不崩。
@MainActor
final class SystemPaneView: MenuPanelPaneView {

    // 属性为 internal（默认）：拆出的 SystemPaneView+Cards.swift 跨文件装配，
    // 同模块内无其他调用方。

    // MARK: 顶部三联

    // 配色只用项目主题单色系：CPU / GPU 走 accent 蓝的明度层级，内存走灰阶（不引入紫 / 青）
    let cpuTile = SystemHeroTileView(label: "CPU", lineColor: MenuPanelStyle.accentColor)
    let gpuTile = SystemHeroTileView(label: "GPU",
                                     lineColor: MenuPanelStyle.accentColor.withAlphaComponent(0.85))
    let memoryTile = SystemHeroTileView(label: "内存", lineColor: MenuPanelStyle.secondaryText)

    // MARK: CPU 卡

    let cpuCard = SystemCardView(title: "CPU")
    let cpuArea = SystemAreaChartView()
    let coreGrid = SystemCoreBarGridView()
    // 卡头双图例（用户态 / 系统态）：与标题同行，不占新增行高
    let cpuSplit = SystemUsageSplitView()

    // MARK: GPU 卡

    let gpuCard = SystemCardView(title: "GPU")
    let gpuRing = SystemRingView()
    let gpuSparkline = SystemSparklineView(lineColor: MenuPanelStyle.accentColor.withAlphaComponent(0.85),
                                           height: 28)
    let gpuMemoryTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.accentColor.withAlphaComponent(0.55))
    let gpuMemoryLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                             font: MenuPanelStyle.smallValueFont,
                                             color: MenuPanelStyle.tertiaryText)

    // MARK: 内存卡

    let memoryCard = SystemCardView(title: "内存")
    let memoryBar = SystemStackedBarView()
    let pressureDot = SystemPressureDotView()
    // 四段数值行（内核对齐原型「单行四段 + 换出量」，不另起一行）
    let memorySplit = SystemMemorySplitView()

    // MARK: 磁盘卡

    let diskCard = SystemCardView(title: "磁盘")
    let diskSparkline = SystemDualSparklineView()
    let diskCapacityTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.accentColor)
    // 速率文字用高对比灰阶（accent / 橙作 9pt 文字在浅色下只有 3.4:1 / 2.0:1）；
    // 读 / 写 的颜色区分改由曲线承担（读 accent、写橙）
    let diskReadLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                            font: MenuPanelStyle.smallValueFont,
                                            color: MenuPanelStyle.secondaryText)
    let diskWriteLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                             font: MenuPanelStyle.smallValueFont,
                                             color: MenuPanelStyle.secondaryText)
    // IOPS 是速率之外的次要编码：9pt 三级灰（不承担颜色区分，颜色留给曲线）
    let diskReadIOPSLabel = MenuPanelLabel.text("读 " + SystemPaneFormat.placeholder,
                                                font: MenuPanelStyle.smallValueFont,
                                                color: MenuPanelStyle.tertiaryText)
    let diskWriteIOPSLabel = MenuPanelLabel.text("写 " + SystemPaneFormat.placeholder,
                                                 font: MenuPanelStyle.smallValueFont,
                                                 color: MenuPanelStyle.tertiaryText)
    // 卡头繁忙度微条：22pt 宽的细条 + 「忙 xx%」，配色沿用磁盘语义橙（原型 --disk-w）
    let diskBusyLabel = MenuPanelLabel.text("忙 " + SystemPaneFormat.placeholder,
                                            font: MenuPanelStyle.smallValueFont,
                                            color: MenuPanelStyle.tertiaryText)
    let diskBusyTrack = MenuPanelTrackView(fillColor: .systemOrange)

    // MARK: 温度卡

    let thermalCard = SystemCardView(title: "温度")
    let thermalValueLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                                font: MenuPanelStyle.heroFont,
                                                color: MenuPanelStyle.tertiaryText)
    let thermalUnitLabel = MenuPanelLabel.text("°C", font: MenuPanelStyle.heroUnitFont,
                                               color: MenuPanelStyle.secondaryText)
    let thermalDetailLabel = MenuPanelLabel.text(SystemPaneFormat.thermalDetail(gpu: nil, power: nil),
                                                 font: MenuPanelStyle.smallValueFont,
                                                 color: MenuPanelStyle.secondaryText)

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        stack.addArrangedSubview(makeHeroRow())
        stack.addArrangedSubview(makeCPUCard())
        stack.addArrangedSubview(makeGPUCard())
        stack.addArrangedSubview(makeMemoryCard())
        stack.addArrangedSubview(makeDiskCard())
        stack.addArrangedSubview(makeThermalCard())
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        update(snapshot: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据更新

    /// 刷新快照 — nil 或子项为 nil 时对应卡片显示「—」（不隐藏、不崩）
    func update(snapshot: SystemMetricsSnapshot?) {
        updateCPU(snapshot?.cpu)
        updateGPU(snapshot?.gpu)
        updateMemory(snapshot?.memory)
        updateDisk(snapshot?.disk)
        updateThermal(snapshot?.thermal)
    }

    // MARK: - 曲线历史（由控制器注入）

    /// 注入 CPU 历史（60 点 1 秒采样；空数组 = 清空曲线）
    func updateHistory(_ history: [Double]) {
        updateHistories(cpu: history)
    }

    /// 注入各图表历史 — 未传入的序列保持原样
    ///
    /// CPU 两段必须同时注入才算「双序列」：只给 `cpu` 时面积图退回单序列画法
    /// （叠加层长度不等会被忽略，曲线照常显示，不会错位成假曲线）。
    func updateHistories(cpu: [Double]? = nil,
                         cpuSystem: [Double]? = nil,
                         gpu: [Double]? = nil,
                         memory: [Double]? = nil,
                         diskRead: [Double]? = nil,
                         diskWrite: [Double]? = nil,
                         diskReadIOPS: [Double]? = nil,
                         diskWriteIOPS: [Double]? = nil) {
        if let cpu {
            let points = SystemChartDrawing.sanitized(cpu)
            cpuTile.update(history: points)
            cpuArea.values = points
        }
        if let cpuSystem {
            cpuArea.overlayValues = SystemChartDrawing.sanitized(cpuSystem)
        }
        if let gpu {
            let points = SystemChartDrawing.sanitized(gpu)
            gpuTile.update(history: points)
            gpuSparkline.values = points
        }
        if let memory {
            memoryTile.update(history: SystemChartDrawing.sanitized(memory))
        }
        if let diskRead {
            diskSparkline.primaryValues = SystemChartDrawing.sanitized(diskRead)
        }
        if let diskWrite {
            diskSparkline.secondaryValues = SystemChartDrawing.sanitized(diskWrite)
        }
        if let diskReadIOPS {
            diskSparkline.primaryOverlayValues = SystemChartDrawing.sanitized(diskReadIOPS)
        }
        if let diskWriteIOPS {
            diskSparkline.secondaryOverlayValues = SystemChartDrawing.sanitized(diskWriteIOPS)
        }
    }

    // MARK: - 派生口径

    // 本段访问级别为 internal：五个 updateXxx 已拆分到 SystemPaneView+Metrics.swift，
    // 跨文件调用需放宽（同模块内除该扩展外无其他调用方）。

    /// 卡头补充：P/E 核数（无分组元数据时退化为总核数）
    func coreSummary(_ snapshot: CPUSnapshot) -> String {
        if snapshot.performanceCores > 0 || snapshot.efficiencyCores > 0 {
            return "\(snapshot.performanceCores)P · \(snapshot.efficiencyCores)E"
        }
        return "\(snapshot.perCore.count) 核"
    }

    /// 每核柱数据：复用 Core 的 P/E 分组口径（P 核在前、E 核在后）
    ///
    /// sysctl 取不到 P/E 核数时 `splitCores` 返回空，此时退化为按顺序展示、不做明度分组。
    func coreBars(_ snapshot: CPUSnapshot) -> [SystemCoreUsage] {
        let split = SystemMetricsFormatting.splitCores(perCore: snapshot.perCore,
                                                       performanceCores: snapshot.performanceCores,
                                                       efficiencyCores: snapshot.efficiencyCores)
        var cores: [SystemCoreUsage] = split.performance.enumerated().map { index, usage in
            SystemCoreUsage(label: "P\(index + 1)", usage: Self.clamp(usage), isPerformance: true)
        }
        cores += split.efficiency.enumerated().map { index, usage in
            SystemCoreUsage(label: "E\(index + 1)", usage: Self.clamp(usage), isPerformance: false)
        }
        if cores.isEmpty {
            cores = snapshot.perCore.enumerated().map { index, usage in
                SystemCoreUsage(label: "\(index + 1)", usage: Self.clamp(usage), isPerformance: true)
            }
        }
        return cores
    }

    /// Core 压力枚举 → 徽标级别（未知按正常显示，避免整条消失）
    func pressureLevel(_ pressure: MemoryPressureLevel) -> SystemPressureDotView.Level {
        if pressure == .critical { return .critical }
        if pressure == .warning { return .warning }
        return .normal
    }

    /// 0...1 钳制（非有限值归零）
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
