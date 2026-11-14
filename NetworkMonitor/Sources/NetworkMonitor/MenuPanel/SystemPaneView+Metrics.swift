import AppKit
import NetworkMonitorCore

// MARK: - 数据更新（拆出主文件）

// 搬移原因：主文件搬出前为 320 行 / 15230 字节，距单文件上限 15360 字节仅余
// 约 130 字节，后续 UI 扩展写不进去，故把逐卡更新整体外置腾出余量。
// 访问级别放宽为 internal：同模块内除 update(snapshot:) 外无其他调用方。

extension SystemPaneView {

    /// CPU：四联数值 + 卡头 P/E 核数与用户态 / 系统态图例 + 卡内 23pt 总利用率
    func updateCPU(_ snapshot: CPUSnapshot?) {
        guard let snapshot else {
            cpuTile.update(value: SystemPaneFormat.placeholder, color: SystemPalette.meta)
            cpuCard.update(nil)
            return
        }
        cpuTile.update(value: SystemPaneFormat.percent(snapshot.totalUsage),
                       color: SystemPalette.cpuInk)
        // total 是唯一真相源：用户态由 total − 系统态现算（口径在卡内图例里），
        // 不读 userUsage 这个独立字段，否则两枚数字各自取整后会凑不出总量。
        cpuCard.update(snapshot)
    }

    /// GPU：四联数值 + 环形利用率 + 显存数值行（版2 不画显存条）
    func updateGPU(_ snapshot: GPUSnapshot?) {
        guard let snapshot else {
            gpuTile.update(value: SystemPaneFormat.placeholder, color: SystemPalette.meta)
            gpuCard.update(nil)
            return
        }
        gpuTile.update(value: SystemPaneFormat.percent(snapshot.utilization),
                       color: SystemPalette.gpuInk)
        gpuCard.update(snapshot)
    }

    /// 内存：四段堆叠条 + 压力徽标 + 卡头容量（版2 不画四段数值行）
    ///
    /// 口径与 Core 一致：已用 = 活跃 + 内核 + 压缩（inactive 不计入，可被回收），
    /// 四段之和等于物理内存总量；任一段缺失（wired / active 都为 0 的老快照）时
    /// 退回「非压缩已用 / 压缩 / 空闲」三段画法，避免整条只剩两段色块。
    func updateMemory(_ snapshot: MemorySnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            memoryTile.update(value: SystemPaneFormat.placeholder, color: SystemPalette.meta)
            memoryCard.update(nil)
            return
        }
        memoryTile.update(value: SystemPaneFormat.percent(
            SystemMetricsFormatting.capacityRatio(used: snapshot.used, total: snapshot.total)
        ), color: SystemPalette.memoryInk)
        // 四段口径与压力态（条描边 + 卡头圆点）都在卡内，见 SystemMemoryCardView.update
        memoryCard.update(snapshot)
    }

    /// 磁盘：版2 只更新卡头 — 繁忙度微条 + 已用 / 总容量 + ›
    ///
    /// IOPS 与繁忙度首帧都是 nil（差分指标没有基线）；nil 一律显示「—」而不是 0，
    /// 否则「刚启动」与「真的没有 IO」在界面上无法区分。
    func updateDisk(_ snapshot: DiskSnapshot?) {
        diskCard.update(snapshot)
    }

    // MARK: - 压力卡（v4）

    /// 负载：三线图 + 卡头三值 + 核数参考线与量程
    func updateLoad(_ snapshot: LoadSnapshot?) {
        guard let snapshot else {
            loadTile.update(value: SystemPaneFormat.placeholder, color: SystemPalette.meta)
            loadCard.update(nil)
            return
        }
        // 主数值取 1 分钟均值（最贴近「此刻压力」），单位由数值自身表达（非百分比）
        loadTile.update(value: String(format: "%.2f", max(0, snapshot.load1)),
                        color: SystemPalette.loadInk)
        // 三值图例、核数标记与纵轴量程都在卡内（量程 = max(核数 × 1.2, 峰值 × 1.15)）
        loadCard.update(snapshot)
        loadCard.toolTip = SystemPaneTip.load(load: snapshot)
    }

    /// 进程榜：按 CPU 占用排序并渲染 Top-2
    func updateProcesses(_ snapshot: ProcessResourceSnapshot?, memoryTotal: UInt64?) {
        processesSnapshot = snapshot
        processesMemoryTotal = memoryTotal
        renderProcessList()
    }

    /// 重绘进程榜（数据刷新共用同一入口，避免两处口径分叉）
    ///
    /// 榜单口径与「压力详情」Top-10 共用（SystemPaneView.processRows），只是条数按首屏取 Top-2。
    func renderProcessList() {
        let rows = processesSnapshot.map {
            Self.processRows($0, metric: .cpu,
                             limit: SystemLoadCardView.rowLimit,
                             memoryTotal: processesMemoryTotal)
        } ?? []
        loadCard.update(processRows: rows)
    }

    /// 采样周期（秒）— 由控制器按设置页偏好注入，详情页据此写「采样 1 秒」
    ///
    /// 页头口径文字同源：五页页头右侧都写一句「这一页的数据按什么节奏来」
    func updateSampleInterval(_ seconds: Double?) {
        sampleIntervalSeconds = seconds
        guard let seconds, seconds.isFinite, seconds > 0 else {
            headerView.updateMeta(nil)
            return
        }
        // 小数周期（1.5s）保一位，整数周期不写小数点
        let text = seconds == seconds.rounded() ? "\(Int(seconds))s" : String(format: "%.1fs", seconds)
        headerView.updateMeta("采样 " + text)
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
