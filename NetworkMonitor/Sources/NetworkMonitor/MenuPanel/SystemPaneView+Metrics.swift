import AppKit
import NetworkMonitorCore

// MARK: - 数据更新（拆出主文件）

// 搬移原因：主文件搬出前为 320 行 / 15230 字节，距单文件上限 15360 字节仅余
// 约 130 字节，后续 UI 扩展写不进去，故把五个 updateXxx 整体外置腾出余量。
// 纯搬移：方法体、文案、注释与主文件原版逐字一致；仅因跨文件访问把
// private 放宽为 internal（同模块内除 update(snapshot:) 外无其他调用方）。

extension SystemPaneView {

    /// CPU：三联小格数值 + 卡头 P/E 核数 + 每核柱阵
    func updateCPU(_ snapshot: CPUSnapshot?) {
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
    func updateGPU(_ snapshot: GPUSnapshot?) {
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
    func updateMemory(_ snapshot: MemorySnapshot?) {
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
    func updateDisk(_ snapshot: DiskSnapshot?) {
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
    func updateThermal(_ snapshot: ThermalSnapshot?) {
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
}
