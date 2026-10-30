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
    static func systemSnapshot(gpu: GPUSnapshot? = GPUSnapshot(utilization: 0.41,
                                                               memoryUsed: 1_600_000_000,
                                                               memoryTotal: nil)) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(
            cpu: CPUSnapshot(totalUsage: 0.37,
                             perCore: [0.12, 0.08, 0.62, 0.71, 0.44, 0.55, 0.38, 0.66, 0.29, 0.51],
                             performanceCores: 8,
                             efficiencyCores: 2,
                             userUsage: 0.22,
                             systemUsage: 0.15),
            gpu: gpu,
            memory: MemorySnapshot(used: 11_200_000_000,
                                   total: 16_000_000_000,
                                   pressure: .normal,
                                   swapUsed: 512_000_000,
                                   swapTotal: 2_000_000_000,
                                   compressed: 1_400_000_000),
            disk: DiskSnapshot(used: 320_000_000_000,
                               total: 494_000_000_000,
                               readBytesPerSecond: 8_400_000,
                               writeBytesPerSecond: 2_100_000),
            // GPU 温度 / 功耗 / 风扇本机恒不可得，默认只给 CPU 温度（与实机一致）
            thermal: ThermalSnapshot(cpuTemperatureCelsius: 56)
        )
    }

    /// 系统页各曲线示意数据（CPU / GPU / 内存为 0...1 比例，磁盘为字节/秒）
    static func systemHistories() -> (cpu: [Double], gpu: [Double], memory: [Double],
                                      diskRead: [Double], diskWrite: [Double]) {
        let cpu = history(base: 0.16, amplitude: 0.42).map { min(1, $0) }
        let gpu = history(base: 0.10, amplitude: 0.35).map { min(1, $0) }
        let memory = history(base: 0.52, amplitude: 0.16).map { min(1, $0) }
        let read = history(base: 2_000_000, amplitude: 9_000_000)
        let write = history(base: 600_000, amplitude: 3_000_000)
        return (cpu, gpu, memory, read, write)
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
