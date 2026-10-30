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


    // MARK: - 压力卡（v4）

    /// 当前进程榜维度
    var processMetric: SystemProcessListView.Metric {
        get { processMetricStorage }
        set { processMetricStorage = newValue }
    }

    /// 负载：三线图 + 卡头三值 + 核数参考线与量程
    func updateLoad(_ snapshot: LoadSnapshot?) {
        guard let snapshot else {
            loadTile.update(value: SystemPaneFormat.placeholder, color: MenuPanelStyle.tertiaryText)
            loadNumbers.update(short: nil, medium: nil, long: nil)
            loadCard.updateTrailing(SystemPaneFormat.placeholder)
            loadChart.coreCount = 0
            loadChart.axisMaximum = 0
            return
        }
        // 主数值取 1 分钟均值（最贴近「此刻压力」），单位由数值自身表达（非百分比）
        loadTile.update(value: String(format: "%.2f", max(0, snapshot.load1)),
                        color: MenuPanelStyle.accentColor)
        loadNumbers.update(short: snapshot.load1, medium: snapshot.load5, long: snapshot.load15)
        // 卡头已有三枚负载数值 + 图例，右侧只留「/10」这种极短核数标记（「核」字进 toolTip）
        loadCard.updateTrailing(snapshot.coreCount > 0 ? "/\(snapshot.coreCount)"
                                : SystemPaneFormat.placeholder)
        loadChart.coreCount = max(0, snapshot.coreCount)
        refreshLoadAxis()
        loadCard.toolTip = SystemPaneTip.load(load: snapshot)
    }

    /// 按当前三序列峰值与核数重算纵轴（cap = max(核数 × 1.2, 峰值 × 1.15)）
    func refreshLoadAxis() {
        let peak = (loadChart.shortValues + loadChart.mediumValues + loadChart.longValues).max() ?? 0
        loadChart.axisMaximum = SystemLoadChartView.axisMaximum(coreCount: loadChart.coreCount,
                                                                peak: peak)
    }

    /// 进程榜：按当前维度排序并渲染 Top-3
    func updateProcesses(_ snapshot: ProcessResourceSnapshot?, memoryTotal: UInt64?) {
        processesSnapshot = snapshot
        processesMemoryTotal = memoryTotal
        renderProcessList()
    }

    /// 按当前维度重绘进程榜（榜单切换与数据刷新共用同一入口，避免两处口径分叉）
    func renderProcessList() {
        let metric = processMetric
        processMetricLabel.stringValue = metric.title
        processMetricLabel.toolTip = SystemPaneTip.processMetric(metric)
        guard let snapshot = processesSnapshot else {
            processList.update([], unavailableTip: SystemPaneTip.processUnavailable)
            return
        }
        let source = metric == .cpu ? snapshot.topCPU : snapshot.topMemory
        let rows = source.prefix(3).map { usage -> SystemProcessListView.Row in
            switch metric {
            case .cpu:
                return SystemProcessListView.Row(
                    name: usage.name,
                    fraction: SystemProcessListView.cpuBarFraction(usage.cpuPercent),
                    valueText: SystemProcessListView.cpuValueText(usage.cpuPercent),
                    isOver: usage.cpuPercent > 100,
                    tip: SystemPaneTip.processRow(usage: usage, metric: .cpu,
                                                  memoryTotal: processesMemoryTotal))
            case .memory:
                return SystemProcessListView.Row(
                    name: usage.name,
                    fraction: SystemProcessListView.memoryBarFraction(
                        residentBytes: usage.residentBytes, totalBytes: processesMemoryTotal ?? 0),
                    valueText: SystemPaneFormat.bytes(usage.residentBytes),
                    isOver: false,
                    tip: SystemPaneTip.processRow(usage: usage, metric: .memory,
                                                  memoryTotal: processesMemoryTotal))
            }
        }
        guard !rows.isEmpty else {
            processList.update([], unavailableTip: SystemPaneTip.processUnavailable)
            return
        }
        processList.update(Array(rows), unavailableTip: SystemPaneTip.processUnavailable)
    }

    /// 电池：底部状态带（无电池机型 / 读取失败时显示「—」）
    func updateBattery(_ snapshot: BatterySnapshot?) {
        lastBatterySnapshot = snapshot
        // Wi-Fi 段同样要重算 toolTip：三段说明共用一段文案，谁刷新都要带上最新的另外两段
        stateBand.updateBattery(snapshot)
        stateBand.toolTip = SystemPaneTip.band(battery: snapshot, thermal: lastThermalSnapshot,
                                               wifi: lastWiFiSnapshot)
    }

    /// 刷新磁盘卡说明里的「近 60 秒繁忙度峰值」— 由历史注入链路调用
    ///
    /// 界面只写当前值，峰值属于口径补充，进 toolTip；无历史（峰值 nil）时回到基础文案。
    func updateDiskBusyTip(busyPeakPercent: Int?) {
        diskCard.toolTip = SystemPaneTip.disk(busyPeakPercent: busyPeakPercent)
    }

    /// Wi-Fi 链路：底部状态带（只放 RSSI 与档位色点）
    func updateWiFiLink(_ snapshot: WiFiLinkSnapshot?) {
        lastWiFiSnapshot = snapshot
        stateBand.updateWiFi(snapshot)
        stateBand.toolTip = SystemPaneTip.band(battery: lastBatterySnapshot,
                                               thermal: lastThermalSnapshot,
                                               wifi: snapshot)
    }

    /// 温度与 GPU 功耗：底部状态带（温度卡在 v4 已下线）
    ///
    /// `powerWatts` 的语义已是 **GPU 功耗（估算）**，不是整机功耗；
    /// 整机功耗不实现（CPU 功耗接口恒为 0，无法合成），故状态带只标「估功耗」。
    func updateThermal(_ snapshot: ThermalSnapshot?) {
        lastThermalSnapshot = snapshot
        stateBand.updateTemperature(snapshot?.cpuTemperatureCelsius)
        stateBand.updatePower(snapshot?.powerWatts)
        stateBand.toolTip = SystemPaneTip.band(battery: lastBatterySnapshot, thermal: snapshot,
                                               wifi: lastWiFiSnapshot)
    }
}
