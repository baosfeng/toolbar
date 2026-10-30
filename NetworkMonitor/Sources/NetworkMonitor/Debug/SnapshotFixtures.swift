#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 快照示意数据

/// 快照专用示意数据 — 折线 / 近 6 日柱状图 / 活跃进程
///
/// 拆到独立文件是为了让 `MenuPanelSnapshot.swift` 回到单文件体积上限（≤15 KiB）内。
/// 这些值只在 `NM_SNAPSHOT_DIR` 快照模式下使用，不参与生产逻辑。
enum SnapshotFixtures {

    /// 折线示意数据：正弦抖动，便于看出折线形状
    static func history(base: Double, amplitude: Double) -> [Double] {
        (0..<60).map { index in
            base + amplitude * (0.5 + 0.5 * sin(Double(index) / 4.0))
        }
    }

    /// 近 6 日柱状图示意数据（时间正序：最左最早、最右今天）
    static func dailyBars() -> [MenuPanelMetrics.DailyTrafficBar] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let values: [UInt64] = [3_100_000_000, 1_800_000_000, 4_200_000_000,
                                2_400_000_000, 5_600_000_000, 2_000_000_000]
        let calendar = Calendar.current
        return values.enumerated().map { offset, value in
            let day = calendar.date(byAdding: .day, value: offset - 5, to: Date()) ?? Date()
            return MenuPanelMetrics.DailyTrafficBar(label: formatter.string(from: day),
                                                    rx: value, tx: value / 5,
                                                    isToday: offset == values.count - 1)
        }
    }

    // MARK: 系统监控示意数据

    /// 系统指标示意快照（数值贴近真实量级，便于核对排版与降级态）
    ///
    /// - Parameters:
    ///   - gpu: 传 nil 构造「GPU 不可用」降级态；默认给利用率与已用显存（本机无显存总量）
    ///   - pressure: 内存压力等级；警告 / 紧张会点亮堆叠条内描边，用于核对压力态表达
    ///   - load: 负载快照；nil 用于核对「负载 + 进程榜」整块降级
    ///   - battery: 电池快照；nil 用于核对无电池 / 电池降级态
    ///   - wifi: Wi-Fi 链路快照；nil 用于核对「无接口 / 关闭 / 未连接」的整条降级态
    static func systemSnapshot(gpu: GPUSnapshot? = GPUSnapshot(utilization: 0.41,
                                                               memoryUsed: 1_600_000_000,
                                                               memoryTotal: nil),
                               pressure: MemoryPressureLevel = .normal,
                               load: LoadSnapshot? = LoadSnapshot(load1: 5.27,
                                                                  load5: 5.51,
                                                                  load15: 6.65,
                                                                  coreCount: 10),
                               battery: BatterySnapshot? = BatterySnapshot(percentage: 0.80,
                                                                           isCharging: false,
                                                                           isOnAC: true,
                                                                           cycleCount: 89),
                               processes: ProcessResourceSnapshot? = nil,
                               showsProcesses: Bool = true,
                               wifi: WiFiLinkSnapshot? = defaultWiFi()) -> SystemMetricsSnapshot {
        // user + system 必须等于 total：卡头用户态由 total − system 现算，
        // 夹具若自相矛盾会让取证图看着对、口径却错
        // 逐核顺序是 E 核在前、P 核在后（splitCores 口径）：E0/E1 高负载、P0–P7 低负载。
        // 逐核均值 = (0.38+0.42+0.012+0.009+0.024+0.018+0.007+0.011+0.009+0.013)/10 ≈ 9.3%，
        // 与卡头 totalUsage 9% 自洽；详情页「P 核均 1.3% · E 核均 40%」也由同一份逐核值算出。
        SystemMetricsSnapshot(
            cpu: CPUSnapshot(totalUsage: 0.09,
                             perCore: [0.38, 0.42, 0.012, 0.009, 0.024, 0.018, 0.007, 0.011, 0.009, 0.013],
                             performanceCores: 8,
                             efficiencyCores: 2,
                             userUsage: 0.052,
                             systemUsage: 0.038),
            gpu: gpu,
            // 四段按 16 GiB 物理内存的比例给：内核 3.6 / 活跃 6.4 / 压缩 1.2 / 空闲 4.8（GiB）；
            // used 必须等于前三段之和，否则卡片会显示「四段之和 ≠ 已用」（口径自相矛盾）
            memory: MemorySnapshot(used: 12_025_908_428,
                                   total: 17_179_869_184,
                                   pressure: pressure,
                                   swapUsed: 0,
                                   swapTotal: 2_000_000_000,
                                   compressed: 1_288_490_188,
                                   active: 6_871_947_674,
                                   wired: 3_865_470_566,
                                   inactive: 1_610_612_736),
            // IOPS / 繁忙度给「高 IOPS、低字节」的小文件随机 IO 量级（最容易被吞吐读数骗过去）
            disk: DiskSnapshot(used: 320_000_000_000,
                               total: 494_000_000_000,
                               readBytesPerSecond: 8_400_000,
                               writeBytesPerSecond: 2_100_000,
                               readIOPS: 128,
                               writeIOPS: 41,
                               busyFraction: 0.12),
            // GPU 温度不可得，只给 CPU 温度（与实机一致）；powerWatts 语义为 GPU 功耗（估算）
            thermal: ThermalSnapshot(cpuTemperatureCelsius: 50, powerWatts: 0.13),
            load: load,
            // 显式开关而非「nil 就补默认值」：noproc 取证态要的正是「进程榜整块不可得」，
            // 用 nil 判定会把降级态又补回默认数据，取证图与满数据态一模一样（踩过）
            processes: showsProcesses ? (processes ?? defaultProcesses()) : nil,
            battery: battery,
            wifi: wifi
        )
    }

    /// 快照模式的 Wi-Fi 链路值 —— 受 `NM_SNAPSHOT_WIFI_MODE=off` 控制
    ///
    /// 网络页与系统页共用这一个入口，保证两页取证图取自同一份数据
    /// （分头各判一次环境变量，迟早出现「网络页有值、系统页 —」的错位证据）。
    static func snapshotWiFi() -> WiFiLinkSnapshot? {
        ProcessInfo.processInfo.environment["NM_SNAPSHOT_WIFI_MODE"] == "off" ? nil : defaultWiFi()
    }

    /// Wi-Fi 链路示意数据 — 取本机实测的一组读数（-63…-66 dBm / 噪声 -96 / ch36 / 5 GHz /
    /// 20 MHz / 103 Mbps / 802.11ax），用于核对链路条与状态带的排版与档位色。
    ///
    /// 只做 **#if DEBUG** 夹具：不进 release、也不喂给生产链路（真实值来自 SystemWiFiLinkSampler）。
    static func defaultWiFi() -> WiFiLinkSnapshot {
        WiFiLinkSnapshot(rssiDBm: -65,
                         noiseDBm: -96,
                         snrDB: 31,
                         channelNumber: 36,
                         band: .band5GHz,
                         channelWidth: .width20MHz,
                         centerFrequencyMHz: 5180,
                         transmitRateMbps: 103,
                         phyMode: .dot11ax,
                         signalQuality: .fair)
    }

    /// 进程榜示意数据 — 10 条覆盖「榜首高占用 / 中段递减 / 碎进程」三档，
    /// 两份榜单由同一批进程排出来（CPU 榜按 CPU%、内存榜按常驻），首屏 Top-2 与详情 Top-10 同源。
    /// 用于核对 sqrt 绝对刻度：条长只由自身 CPU% 决定，与榜首是谁无关。
    static func defaultProcesses() -> ProcessResourceSnapshot {
        let rows = [
            ProcessResourceUsage(pid: 431, name: "qemu-system-aar", cpuPercent: 73.9,
                                 residentBytes: 2_400_000_000),
            ProcessResourceUsage(pid: 918, name: "WindowServer", cpuPercent: 41.2,
                                 residentBytes: 1_100_000_000),
            ProcessResourceUsage(pid: 2261, name: "Xcode", cpuPercent: 27.6,
                                 residentBytes: 3_900_000_000),
            ProcessResourceUsage(pid: 77, name: "mds_stores", cpuPercent: 18.8,
                                 residentBytes: 620_000_000),
            ProcessResourceUsage(pid: 1502, name: "Terminal", cpuPercent: 12.4,
                                 residentBytes: 210_000_000),
            ProcessResourceUsage(pid: 302, name: "DeepSeek", cpuPercent: 8.6,
                                 residentBytes: 1_500_000_000),
            ProcessResourceUsage(pid: 655, name: "Safari", cpuPercent: 5.2,
                                 residentBytes: 980_000_000),
            ProcessResourceUsage(pid: 812, name: "WeChat", cpuPercent: 3.1,
                                 residentBytes: 740_000_000),
            ProcessResourceUsage(pid: 933, name: "Spotify", cpuPercent: 1.8,
                                 residentBytes: 320_000_000),
            ProcessResourceUsage(pid: 1044, name: "Finder", cpuPercent: 0.9,
                                 residentBytes: 180_000_000),
        ]
        return ProcessResourceSnapshot(
            topCPU: rows.sorted { $0.cpuPercent > $1.cpuPercent },
            topMemory: rows.sorted { $0.residentBytes > $1.residentBytes },
            scannedCount: 512)
    }

    /// 高负载示意：三线远超核数（10），配合 thermalState = critical 核对「排队」表达
    static func highLoadSnapshot() -> LoadSnapshot {
        LoadSnapshot(load1: 78.4, load5: 64.2, load15: 41.7,
                     coreCount: 10, thermalState: .critical)
    }

    /// 系统页各曲线示意数据（CPU / GPU / 内存为 0...1 比例，磁盘速率为字节/秒，IOPS 为次/秒）
    ///
    /// CPU 系统态序列与总量同相位但恒小于总量：叠加带厚度即系统态占比，
    /// 若两条各自独立随机会出现「带比总量还高」的假读数。
    static func systemHistories() -> (cpu: [Double], cpuSystem: [Double], gpu: [Double],
                                      memory: [Double],
                                      memoryWired: [Double], memoryActive: [Double],
                                      memoryCompressed: [Double],
                                      diskRead: [Double], diskWrite: [Double],
                                      loadShort: [Double], loadMedium: [Double],
                                      loadLong: [Double]) {
        // 与快照卡头同量级（9%）：曲线均值约 9%，不出现「卡头 9%、曲线却冲到 58%」的假读数
        let cpu = history(base: 0.05, amplitude: 0.08).map { min(1, $0) }
        // 系统态占比与快照卡头同口径（15% ÷ 37% ≈ 0.41），图例与带厚才对得上
        let cpuSystem = cpu.map { $0 * 0.41 }
        let gpu = history(base: 0.10, amplitude: 0.35).map { min(1, $0) }
        let memory = history(base: 0.52, amplitude: 0.16).map { min(1, $0) }
        // 三段堆叠趋势：占比口径（wired 11% / active 29% / compressed 24%），三段之和 = 已用占比
        let wired = history(base: 0.11, amplitude: 0.04).map { min(0.20, max(0, $0)) }
        let active = history(base: 0.29, amplitude: 0.10).map { min(0.45, max(0, $0)) }
        let compressed = history(base: 0.24, amplitude: 0.08).map { min(0.38, max(0, $0)) }
        let read = history(base: 2_000_000, amplitude: 9_000_000)
        let write = history(base: 600_000, amplitude: 3_000_000)
        // 负载三线围核数（10）上下抖动：1m 抖得最凶、15m 最平（长窗口天然滞后），
        // 让三线既越过参考虚线又留有回落区间——「越过即排队」的表达才看得见
        let load1 = history(base: 8.5, amplitude: 7.0)
        let load5 = history(base: 7.6, amplitude: 3.4)
        let load15 = history(base: 6.6, amplitude: 1.6)
        return (cpu, cpuSystem, gpu, memory, wired, active, compressed,
                read, write, load1, load5, load15)
    }

    /// 活跃进程示意数据（进程名真实 → 可验证 NSWorkspace 真实图标解析）
    ///
    /// - Parameter count: 条数；超过 5 条时用于「内容高于 520pt」的可滚动自证
    static func processes(count: Int = 5) -> [ProcessNetUsage] {
        let names = ["Safari", "Google Chrome", "Terminal", "WeChat", "Spotify",
                     "Xcode", "Slack", "Notes", "Mail", "Finder", "Firefox", "Discord"]
        return (0..<max(0, count)).map { index in
            let name = names[index % names.count] + (index < names.count ? "" : " \(index + 1)")
            return ProcessNetUsage(name: name, pid: Int32(1200 + index),
                                   bytesIn: UInt64(1_200_000 / (index + 1)),
                                   bytesOut: UInt64(90_000 / (index + 1)))
        }
    }
}
#endif
