import AppKit
import NetworkMonitorCore

// MARK: - 系统页卡片 toolTip 文案

/// 系统页各卡与详情页的 `toolTip` 文案 — 界面只留数值与 ≤4 字标签，口径 / 来源 / 不可得原因全部走这里
///
/// 集中一处：卡片装配、历史刷新与详情页三条链路要写同一份说明，散落两处必然走样。
enum SystemPaneTip {

    // MARK: 首屏五卡（版2）

    /// CPU 卡：总占用口径 + 用户态 / 系统态双序列 + 每核数据的去向
    static let cpu = "CPU 利用率 = 1 − 空闲占比；USER + SYSTEM + NICE + IRQ ticks 差分 ÷ 全部 ticks（含 idle），"
        + "1 秒采样。图上浅蓝面积 = 用户态（应用与用户进程），其上深色带 = 系统态（内核与驱动），"
        + "带顶线为总占用；两段同处 0…100 刻度，带厚即系统态真实占比，不是量程换算。"
        + "每核占用（P0–P7 / E0–E1）已下沉到 CPU 详情页，点卡片进入"

    /// GPU 卡：利用率 + 显存数值
    static let gpu = "GPU 利用率为设备性能计数器读数；折线为最近 60 秒趋势；"
        + "显存只给已用量（统一内存机型取不到总量，故不画占比条，取不到时显示「—」）；"
        + "显存总量说明与 0–10% 量程曲线在 GPU 详情页"

    /// 内存卡：四段条与压力的口径（四段数值下沉到详情页）
    static let memory = "物理内存四段（按物理内存占比）：深色 = 内核 wired（不可换出、不可压缩，源 wire_count）、"
        + "主色 = 活跃 active（应用页，源 active_count）、浅色 = 压缩 compressed（压缩器实际物理占用，"
        + "源 compressor_page_count，是压缩后的物理占用而非压缩前体量）、空白 = 空闲 free；"
        + "四段之和等于物理内存总量，已用 = 活跃 + 内核 + 压缩，不含 inactive（可被系统随时回收，"
        + "计进去读数会长期偏高）。圆点为系统内存压力（绿正常、琥珀警告、红严重，"
        + "源 kern.memorystatus_vm_pressure_level）。四段数值与占比、60 点堆叠趋势在内存详情页"

    /// 磁盘卡：版2 单行口径
    ///
    /// - Parameter busyPeakPercent: 近 60 秒繁忙度峰值（百分数）；nil 表示尚无历史
    static func disk(busyPeakPercent: Int?) -> String {
        let base = "磁盘卡只保留卡头：繁忙度 =（读服务时间 + 写服务时间）÷ 采样间隔，即设备处于 IO 的时间占比，"
            + "走磁盘族石墨（「忙」是设备占用率，与读序列同色；写序列才是琥珀）；"
            + "容量取自根卷属性（含系统与用户数据）。"
            + "读写速率（Bytes 差分 ÷ 采样间隔）、读/写 IOPS（Operations 差分，次/秒）、"
            + "繁忙度明细、60 秒读写双序列与可用容量都在磁盘详情页。"
            + "IOPS / 繁忙度与字节速率同一次 IOBlockStorageDriver 调用取回，零额外采样开销；"
            + "该机型未返回 Operations / Total Time 键时 IOPS 与繁忙度显示「—」，字节速率照常"
        guard let busyPeakPercent else { return base }
        return base + "；近 60 秒繁忙度峰值 \(busyPeakPercent)%"
    }

    /// 压力卡：负载口径 + 量程 + 进程榜口径（有负载快照时补核数与热压力）
    static func load(load snapshot: LoadSnapshot? = nil) -> String {
        let base = "压力 = 就绪队列多长（上半）+ 谁在吃 CPU（下半）。"
            + "负载三线为 1 / 5 / 15 分钟指数均值（getloadavg，非百分比而是就绪队列长度）；"
            + "虚线为核数参考位，按 核数 / 纵轴上限 的真实比例画——三线越过虚线即「有进程在排队」，"
            + "此时 CPU% 仍可能不高（它只反映已占用时间，看不到排队）。"
            + "纵轴不是固定 0–100%：上限 = max(核数 × 1.2, 近 60 秒峰值 × 1.15)，"
            + "下限用核数避免低负载把噪声放大成满画布，上限用峰值让三线用满高度。"
            + "进程榜取 proc_pidinfo 全量遍历（约 1.3ms/次），CPU% 为 1 秒差分，单进程可 >100%（多线程合法）；"
            + "条形为 sqrt 绝对刻度（满条 = 100% = 占满一个核），只取决于该进程自身 CPU%，不随榜首联动。"
            + "版2 只显示 Top-2，卡头「全部 ›」进 CPU 详情（每核 + 忙闲拆分）"
        guard let snapshot else { return base }
        var detail = base + "。本帧核数 \(max(0, snapshot.coreCount))"
        if snapshot.thermalState != .unknown {
            detail += "，热压力 \(thermalStateText(snapshot.thermalState))"
        }
        if snapshot.isLowPowerModeEnabled {
            detail += "，低电量模式已开启（系统会主动降频）"
        }
        return detail
    }

    /// 热压力等级 → 界面用词
    private static func thermalStateText(_ state: ThermalStateLevel) -> String {
        switch state {
        case .nominal: return "正常"
        case .fair: return "轻微"
        case .serious: return "严重"
        case .critical: return "临界"
        case .unknown: return "未知"
        }
    }

    /// 进程榜不可得
    static let processUnavailable = "进程读数不可得 · 首帧差分需要两个采样点，"
        + "或 proc_pidinfo 全部返回 -1（权限 / 僵尸进程）；本机实测多数进程有差分值，属正常现象"

    /// 卡头「全部 ›」
    static let processAll = "进 CPU 详情：每核热力格（P0–P7 / E0–E1 逐核百分比）+ 忙闲拆分"

    /// 榜单维度说明（压力详情页切换按钮）
    static func processMetric(_ metric: SystemProcessMetric) -> String {
        switch metric {
        case .cpu:
            return "CPU 榜 · 按 CPU 占用降序 · 1 秒差分（proc_pidinfo）。单进程可 >100%（多线程合法，"
                + "如实显示原值不 clamp，超 100% 转琥珀）；条形为 sqrt 绝对刻度，满条 = 占满一个核"
        case .memory:
            return "内存榜 · 按常驻内存（RSS）降序；条形为 常驻 / 物理内存 的线性占比"
        }
    }

    /// 切换按钮
    static let processToggle = "切换榜单维度：CPU 占用降序 / 常驻内存降序"

    /// 单行进程说明
    ///
    /// - Parameter displayName: 行的显示名（本应用那行已由 `AppProcessName` 换成「一览」）——
    ///   与行内标签同源，避免悬停说明写英文名、行里却是中文名
    static func processRow(usage: ProcessResourceUsage,
                           displayName: String,
                           metric: SystemProcessMetric,
                           memoryTotal: UInt64?) -> String {
        switch metric {
        case .cpu:
            return "\(displayName) · pid \(usage.pid) · CPU \(String(format: "%.2f", usage.cpuPercent))%"
                + "（多线程可 >100%，满条即一个核）；常驻内存 \(SystemPaneFormat.bytes(usage.residentBytes))"
        case .memory:
            let totalText = memoryTotal.map { SystemPaneFormat.bytes($0) } ?? SystemPaneFormat.placeholder
            return "\(displayName) · pid \(usage.pid) · 常驻内存 \(SystemPaneFormat.bytes(usage.residentBytes))"
                + " / 物理内存 \(totalText)；当前 CPU \(String(format: "%.1f", usage.cpuPercent))%"
        }
    }

    // MARK: 底部状态带

    /// 状态带：温度来源 + 电池口径 + Wi-Fi 口径 + 估算功耗 + 不可得项
    ///
    /// - Parameter wifi: Wi-Fi 链路快照；nil 时补一句「为什么是 —」，与链路条同一份措辞
    static func band(battery: BatterySnapshot?, thermal: ThermalSnapshot?,
                     wifi: WiFiLinkSnapshot? = nil) -> String {
        var parts = ["SoC 温度取自从 IOHIDEventSystemClient 读到的事件字段（非 SMC 键，超过 85°C 转警示色）"]
        if let battery {
            var batteryText = "电池电量来自 IOPSGetPowerSourceDescription 的 Current Capacity"
            if let cycles = battery.cycleCount {
                batteryText += "，循环次数 \(cycles) / 1000（AppleSmartBattery CycleCount / DesignCycleCount9C）"
            }
            batteryText += "；健康度百分比严格不可得（51 个属性里既无 BatteryHealth 也无 DesignCapacity），故只给循环次数"
            parts.append(batteryText)
            if let watts = battery.adapterWatts {
                parts.append(String(format: "外接电源适配器标称 %.0f W", watts))
            }
        } else {
            parts.append("电池读数不可得（本机可能无电池或 AppleSmartBattery 未暴露），显示「—」")
        }
        parts.append("Wi-Fi 段只放 RSSI 与档位色点，信道 / 速率在状态带宽度里放不下（在「网络」页的链路条上）；"
            + WiFiLinkFormatting.toolTip(wifi))
        parts.append("「估功耗」为 GPU 功耗估算值（IOReport Energy Model 的 GPU Energy 累加器，单位 nJ ÷ 1e9 ÷ 窗口秒数），非精确功耗计读数；CPU 功耗恒为 0，故不合成整机功耗")
        parts.append("GPU 独立温度与风扇转速完全不可得，不出该项")
        if let thermal, thermal.isEmpty {
            parts.append("本帧温度读数不可得")
        }
        return parts.joined(separator: "；")
    }
}
