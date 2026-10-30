import AppKit
import NetworkMonitorCore

// MARK: - 数据更新（拆出主文件）

// 搬移原因：主文件搬出前为 320 行 / 15230 字节，距单文件上限 15360 字节仅余
// 约 130 字节，后续 UI 扩展写不进去，故把五个 updateXxx 整体外置腾出余量。
// 纯搬移：方法体、文案、注释与主文件原版逐字一致；仅因跨文件访问把
// private 放宽为 internal（同模块内除 update(snapshot:) 外无其他调用方）。

extension SystemPaneView {

    /// CPU：三联小格数值 + 卡头 P/E 核数与用户态 / 系统态图例 + 每核柱阵
    func updateCPU(_ snapshot: CPUSnapshot?) {
        guard let snapshot else {
            cpuTile.update(value: SystemPaneFormat.placeholder, color: MenuPanelStyle.tertiaryText)
            cpuCard.updateTrailing(SystemPaneFormat.placeholder)
            cpuSplit.update(total: nil, system: nil)
            coreGrid.cores = []
            return
        }
        cpuTile.update(value: SystemPaneFormat.percent(snapshot.totalUsage),
                       color: MenuPanelStyle.accentColor)
        cpuCard.updateTrailing(coreSummary(snapshot))
        // total 是唯一真相源：用户态由 total − 系统态现算，不读 userUsage 这个独立字段。
        // 否则两枚数字各自取整后会凑不出总量（如「总 25 / 用户 13 / 系统 13」），
        // 与图上叠加带（带厚 = 系统态、带顶 = 总量）也对不上。
        cpuSplit.update(total: snapshot.totalUsage, system: snapshot.systemUsage)
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

    /// 内存：四段堆叠条 + 压力徽标 + 四段数值与换出量
    ///
    /// 口径与 Core 一致：已用 = 活跃 + 内核 + 压缩（inactive 不计入，可被回收），
    /// 四段之和等于物理内存总量；任一段缺失（wired / active 都为 0 的老快照）时
    /// 退回「非压缩已用 / 压缩 / 空闲」三段画法，避免整条只剩两段色块。
    func updateMemory(_ snapshot: MemorySnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            memoryTile.update(value: SystemPaneFormat.placeholder, color: MenuPanelStyle.tertiaryText)
            memoryCard.updateTrailing(SystemPaneFormat.placeholder)
            memoryBar.segments = []
            memoryBar.total = 0
            memoryBar.pressureLevel = .unknown
            pressureDot.level = .unknown
            memorySplit.reset()
            return
        }
        let total = Double(snapshot.total)
        let used = min(Double(snapshot.used), total)
        let wired = min(Double(snapshot.wired), used)
        let compressed = min(Double(snapshot.compressed), max(0, used - wired))
        let active = max(0, used - wired - compressed)
        let free = max(0, total - used)
        memoryBar.total = total
        if snapshot.wired > 0 || snapshot.active > 0 {
            memoryBar.segments = [
                .init(value: wired, color: SystemPaneStyle.memoryWired),
                .init(value: active, color: SystemPaneStyle.memoryActive),
                .init(value: compressed, color: SystemPaneStyle.memoryCompressed),
                .init(value: free, color: .clear),
            ]
        } else {
            // 老快照未拆分 wired / active：非压缩已用合并为一段，仍保持四段槽位形状
            memoryBar.segments = [
                .init(value: used - compressed, color: SystemPaneStyle.memoryActive),
                .init(value: compressed, color: SystemPaneStyle.memoryCompressed),
                .init(value: free, color: .clear),
            ]
        }
        memoryTile.update(value: SystemPaneFormat.percent(
            SystemMetricsFormatting.capacityRatio(used: snapshot.used, total: snapshot.total)
        ), color: MenuPanelStyle.secondaryText)
        memoryCard.updateTrailing(SystemPaneFormat.bytes(snapshot.used) + " / "
                                  + SystemPaneFormat.bytes(snapshot.total))
        // 压力态同时反映到堆叠条描边与卡头圆点：只看条形时也要能读出「警示 / 紧张」
        let level = pressureLevel(snapshot.pressure)
        memoryBar.pressureLevel = level
        pressureDot.level = level
        memorySplit.update(wired: snapshot.wired,
                           active: active > 0 ? UInt64(active) : snapshot.active,
                           compressed: snapshot.compressed,
                           free: UInt64(free),
                           swapUsed: snapshot.swapUsed)
    }

    /// 磁盘：容量条 + 读写速率 + 读写 IOPS + 卡头繁忙度
    ///
    /// IOPS 与繁忙度首帧都是 nil（差分指标没有基线）；nil 一律显示「—」而不是 0，
    /// 否则「刚启动」与「真的没有 IO」在界面上无法区分。
    func updateDisk(_ snapshot: DiskSnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            diskCard.updateTrailing(SystemPaneFormat.placeholder)
            diskCapacityTrack.fraction = 0
            diskReadLabel.stringValue = SystemPaneFormat.placeholder
            diskWriteLabel.stringValue = SystemPaneFormat.placeholder
            diskReadIOPSLabel.stringValue = "读 " + SystemPaneFormat.placeholder
            diskWriteIOPSLabel.stringValue = "写 " + SystemPaneFormat.placeholder
            diskBusyLabel.stringValue = "忙 " + SystemPaneFormat.placeholder
            diskBusyTrack.fraction = 0
            return
        }
        diskCapacityTrack.fraction = SystemMetricsFormatting.capacityRatio(used: snapshot.used,
                                                                         total: snapshot.total)
        diskCard.updateTrailing(SystemPaneFormat.bytes(snapshot.used) + " / "
                                + SystemPaneFormat.bytes(snapshot.total))
        diskReadLabel.stringValue = SystemPaneFormat.rate(snapshot.readBytesPerSecond)
        diskWriteLabel.stringValue = SystemPaneFormat.rate(snapshot.writeBytesPerSecond)
        // IOPS 与繁忙度同属一批计数器：三键任一不可得就整组降级为「—」，
        // 不留「有数值无虚线」或「有虚线无数值」的半显状态（三键必然同源同缺）。
        let iopsAvailable = snapshot.readIOPS != nil && snapshot.writeIOPS != nil
            && snapshot.busyFraction != nil
        diskReadIOPSLabel.stringValue = iopsAvailable
            ? "读 " + SystemPaneFormat.iops(snapshot.readIOPS) : "读 " + SystemPaneFormat.placeholder
        diskWriteIOPSLabel.stringValue = iopsAvailable
            ? "写 " + SystemPaneFormat.iops(snapshot.writeIOPS) : "写 " + SystemPaneFormat.placeholder
        diskBusyLabel.stringValue = "忙 "
            + (iopsAvailable ? SystemPaneFormat.percent(snapshot.busyFraction) : SystemPaneFormat.placeholder)
        diskBusyTrack.fraction = iopsAvailable
            ? SystemPaneFormat.unitFraction(snapshot.busyFraction) : 0
        // 虚线随数值一起撤：没有数值的曲线是自相矛盾的读数
        if !iopsAvailable {
            diskSparkline.primaryOverlayValues = []
            diskSparkline.secondaryOverlayValues = []
        }
    }

    /// 刷新磁盘卡说明里的「近 60 秒繁忙度峰值」— 由历史注入链路调用
    ///
    /// 界面只写当前值，峰值属于口径补充，进 toolTip；无历史（峰值 nil）时回到基础文案。
    func updateDiskBusyTip(busyPeakPercent: Int?) {
        diskCard.toolTip = SystemPaneTip.disk(busyPeakPercent: busyPeakPercent)
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
