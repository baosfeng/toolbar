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
    let memorySwapLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                              font: MenuPanelStyle.smallValueFont,
                                              color: MenuPanelStyle.secondaryText)

    // MARK: 磁盘卡

    let diskCard = SystemCardView(title: "磁盘")
    let diskSparkline = SystemDualSparklineView()
    let diskCapacityTrack = MenuPanelTrackView(fillColor: MenuPanelStyle.accentColor)
    // 速率文字用高对比灰阶（accent / 橙作 9pt 文字在浅色下只有 3.4:1 / 2.0:1）；
    // 读 / 写 的颜色区分改由曲线承担（读 accent、写橙）
    let diskReadLabel = MenuPanelLabel.text("读 " + SystemPaneFormat.placeholder,
                                            font: MenuPanelStyle.smallValueFont,
                                            color: MenuPanelStyle.secondaryText)
    let diskWriteLabel = MenuPanelLabel.text("写 " + SystemPaneFormat.placeholder,
                                             font: MenuPanelStyle.smallValueFont,
                                             color: MenuPanelStyle.secondaryText)

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

    /// CPU：三联小格数值 + 卡头 P/E 核数 + 每核柱阵
    private func updateCPU(_ snapshot: CPUSnapshot?) {
        guard let snapshot else {
            cpuTile.update(value: SystemPaneFormat.placeholder, color: MenuPanelStyle.tertiaryText)
            cpuCard.updateTrailing(SystemPaneFormat.placeholder)
            coreGrid.cores = []
            return
        }
        cpuTile.update(value: SystemPaneFormat.percent(snapshot.totalUsage),
                       color: MenuPanelStyle.accentColor)
        cpuCard.updateTrailing(coreSummary(snapshot))
        coreGrid.cores = coreBars(snapshot)
    }

    /// GPU：环形利用率 + 显存细条
    private func updateGPU(_ snapshot: GPUSnapshot?) {
        guard let snapshot else {
            gpuTile.update(value: SystemPaneFormat.placeholder, color: MenuPanelStyle.tertiaryText)
            gpuRing.fraction = 0
            gpuRing.centerText = SystemPaneFormat.placeholder
            gpuMemoryTrack.fraction = 0
            gpuMemoryLabel.stringValue = SystemPaneFormat.placeholder
            return
        }
        let utilization = Self.clamp(snapshot.utilization)
        gpuTile.update(value: SystemPaneFormat.percent(utilization), color: MenuPanelStyle.accentColor)
        gpuRing.fraction = utilization
        gpuRing.centerText = SystemPaneFormat.percent(utilization)
        if let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 {
            gpuMemoryTrack.fraction = SystemMetricsFormatting.capacityRatio(used: used, total: total)
            gpuMemoryLabel.stringValue = SystemPaneFormat.bytes(used) + " / "
                + SystemPaneFormat.bytes(total)
        } else if let used = snapshot.memoryUsed {
            // 统一内存机型取不到显存总量：只给已用量，细条留空（不显示半条假比例）
            gpuMemoryTrack.fraction = 0
            gpuMemoryLabel.stringValue = SystemPaneFormat.bytes(used)
        } else {
            gpuMemoryTrack.fraction = 0
            gpuMemoryLabel.stringValue = SystemPaneFormat.placeholder
        }
    }

    /// 内存：堆叠条 + 压力徽标 + SWAP
    private func updateMemory(_ snapshot: MemorySnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            memoryTile.update(value: SystemPaneFormat.placeholder, color: MenuPanelStyle.tertiaryText)
            memoryCard.updateTrailing(SystemPaneFormat.placeholder)
            memoryBar.segments = []
            memoryBar.total = 0
            pressureDot.level = .unknown
            memorySwapLabel.stringValue = SystemPaneFormat.placeholder
            return
        }
        let total = Double(snapshot.total)
        let used = min(Double(snapshot.used), total)
        // 快照只给 used 与 compressed：非压缩段 = used - compressed（wired + active 合并）
        let compressed = min(Double(snapshot.compressed), used)
        let free = max(0, total - used)
        memoryBar.total = total
        memoryBar.segments = [
            .init(value: used - compressed,
                  color: MenuPanelStyle.accentColor.withAlphaComponent(0.90)),
            .init(value: compressed, color: MenuPanelStyle.accentColor.withAlphaComponent(0.58)),
            .init(value: free, color: MenuPanelStyle.trackColor),
        ]
        memoryTile.update(value: SystemPaneFormat.percent(
            SystemMetricsFormatting.capacityRatio(used: snapshot.used, total: snapshot.total)
        ), color: MenuPanelStyle.secondaryText)
        memoryCard.updateTrailing(SystemPaneFormat.bytes(snapshot.used) + " / "
                                  + SystemPaneFormat.bytes(snapshot.total))
        pressureDot.level = pressureLevel(snapshot.pressure)
        if snapshot.swapTotal > 0 {
            memorySwapLabel.stringValue = SystemPaneFormat.bytes(snapshot.swapUsed) + " / "
                + SystemPaneFormat.bytes(snapshot.swapTotal)
        } else {
            memorySwapLabel.stringValue = SystemPaneFormat.bytes(snapshot.swapUsed) + " / "
                + SystemPaneFormat.placeholder
        }
    }

    /// 磁盘：容量条 + 读写速率
    private func updateDisk(_ snapshot: DiskSnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            diskCard.updateTrailing(SystemPaneFormat.placeholder)
            diskCapacityTrack.fraction = 0
            diskReadLabel.stringValue = "读 " + SystemPaneFormat.placeholder
            diskWriteLabel.stringValue = "写 " + SystemPaneFormat.placeholder
            return
        }
        diskCapacityTrack.fraction = SystemMetricsFormatting.capacityRatio(used: snapshot.used,
                                                                         total: snapshot.total)
        diskCard.updateTrailing(SystemPaneFormat.bytes(snapshot.used) + " / "
                                + SystemPaneFormat.bytes(snapshot.total))
        diskReadLabel.stringValue = "读 " + SystemPaneFormat.rate(snapshot.readBytesPerSecond)
        diskWriteLabel.stringValue = "写 " + SystemPaneFormat.rate(snapshot.writeBytesPerSecond)
    }

    /// 温度：CPU hero（>85°C 警示色）+ GPU 温度 / 功耗
    private func updateThermal(_ snapshot: ThermalSnapshot?) {
        guard let snapshot else {
            thermalValueLabel.stringValue = SystemPaneFormat.placeholder
            thermalValueLabel.textColor = MenuPanelStyle.tertiaryText
            thermalDetailLabel.stringValue = SystemPaneFormat.thermalDetail(gpu: nil, power: nil)
            return
        }
        let celsius = snapshot.cpuTemperatureCelsius
        thermalValueLabel.stringValue = SystemPaneFormat.temperatureNumber(celsius)
        if let celsius, celsius.isFinite, celsius > SystemPaneFormat.hotThreshold {
            thermalValueLabel.textColor = NSColor.systemRed
        } else if celsius == nil {
            thermalValueLabel.textColor = MenuPanelStyle.tertiaryText
        } else {
            thermalValueLabel.textColor = .labelColor
        }
        thermalDetailLabel.stringValue = SystemPaneFormat.thermalDetail(
            gpu: snapshot.gpuTemperatureCelsius,
            power: snapshot.powerWatts
        )
    }

    // MARK: - 曲线历史（由控制器注入）

    /// 注入 CPU 历史（60 点 1 秒采样；空数组 = 清空曲线）
    func updateHistory(_ history: [Double]) {
        updateHistories(cpu: history)
    }

    /// 注入各图表历史 — 未传入的序列保持原样
    func updateHistories(cpu: [Double]? = nil,
                         gpu: [Double]? = nil,
                         memory: [Double]? = nil,
                         diskRead: [Double]? = nil,
                         diskWrite: [Double]? = nil) {
        if let cpu {
            let points = SystemChartDrawing.sanitized(cpu)
            cpuTile.update(history: points)
            cpuArea.values = points
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
    }

    // MARK: - 派生口径

    /// 卡头补充：P/E 核数（无分组元数据时退化为总核数）
    private func coreSummary(_ snapshot: CPUSnapshot) -> String {
        if snapshot.performanceCores > 0 || snapshot.efficiencyCores > 0 {
            return "\(snapshot.performanceCores)P · \(snapshot.efficiencyCores)E"
        }
        return "\(snapshot.perCore.count) 核"
    }

    /// 每核柱数据：复用 Core 的 P/E 分组口径（P 核在前、E 核在后）
    ///
    /// sysctl 取不到 P/E 核数时 `splitCores` 返回空，此时退化为按顺序展示、不做明度分组。
    private func coreBars(_ snapshot: CPUSnapshot) -> [SystemCoreUsage] {
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
    private func pressureLevel(_ pressure: MemoryPressureLevel) -> SystemPressureDotView.Level {
        if pressure == .critical { return .critical }
        if pressure == .warning { return .warning }
        return .normal
    }

    /// 0...1 钳制（非有限值归零）
    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
