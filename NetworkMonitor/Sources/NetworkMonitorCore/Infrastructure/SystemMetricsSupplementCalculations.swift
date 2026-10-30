import Foundation

// MARK: - 第二批指标纯计算（负载归一化 / 进程 Top-N / 功耗换算）
//
// 采样器落在 NetworkMonitor 目标（libproc / IOReport / IOPS 只能在可执行目标），
// TestRunner 只依赖 NetworkMonitorCore，因此口径全部下沉到这里：采样器只读原始计数，
// 换算、排序、截断与降级判定在本文件可测。

/// 单帧进程 CPU 差分结果（采样器填 Baseline，纯函数算百分比）
public struct ProcessCPUTimeBaseline: Sendable, Equatable {
    /// 进程 CPU 累计时间（mach ticks，**不是纳秒**）
    public let cpuTicks: UInt64
    /// 进程常驻内存（字节）
    public let residentBytes: UInt64

    public init(cpuTicks: UInt64, residentBytes: UInt64) {
        self.cpuTicks = cpuTicks
        self.residentBytes = residentBytes
    }
}

// MARK: - 纯计算

public enum SystemMetricsSupplementCalculations {

    // MARK: 负载

    /// 负载归一化（load / 逻辑核数）
    ///
    /// 语义：返回值 > 1 表示有进程在排队等 CPU。
    /// - 核数 ≤ 0（取不到）→ nil：不猜分母，让 UI 显示原始负载；
    /// - 负载为负或非有限 → nil（getloadavg 失败时的脏值不展示成 0）；
    /// - 结果不封顶：排队越严重越该显眼，封顶会掩盖过载。
    public static func normalizedLoad(_ load: Double, coreCount: Int) -> Double? {
        guard coreCount > 0, load.isFinite, load >= 0 else { return nil }
        return load / Double(coreCount)
    }

    // MARK: 进程 CPU%

    /// 由两次累计 tick 算进程 CPU 百分比（单核百分比，可 > 100）
    ///
    /// **时基是本指标最致命的坑**：pti_total_user/system 的单位是 mach ticks，
    /// Apple Silicon 上 mach_timebase_info = 125/3（1 tick ≈ 41.6667 ns），
    /// 按纳秒直接换算会系统性偏小 41.67 倍（3 线程自旋实测 7.2% vs 正确 298%）。
    /// 因此 nsPerTick 必须由调用方运行时传入，禁止硬编码 41.6667
    /// （Intel 机型 timebase 为 1/1，硬编码会反向放大 41.67 倍）。
    ///
    /// - elapsedSeconds ≤ 0 或非有限 → nil（不除零）；
    /// - 累计值倒退（进程重置 / 计数器回绕）→ nil，不返回负百分比；
    /// - 结果**不 clamp 到 100**：多线程进程合法超过 100%，削平会让 Top-N 排序错乱。
    public static func cpuPercent(previousTicks: UInt64,
                                  currentTicks: UInt64,
                                  nanosecondsPerTick: Double,
                                  elapsedSeconds: TimeInterval) -> Double? {
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return nil }
        guard nanosecondsPerTick > 0, nanosecondsPerTick.isFinite else { return nil }
        guard currentTicks >= previousTicks else { return nil }
        let cpuSeconds = Double(currentTicks - previousTicks) * nanosecondsPerTick / 1_000_000_000
        let percent = cpuSeconds / elapsedSeconds * 100
        return percent.isFinite ? percent : nil
    }

    /// 由 tick 表算 Top-N 两份榜单
    ///
    /// 入参是「pid → (累计 ticks, 常驻字节)」，其中 ticks 为本次采样值，
    /// previous 为空表示首帧（无基线）：首帧直接返回 nil，不把「还没测」显示成 0。
    ///
    /// 边界：
    /// - 首帧 / 本次为空 / 时间差非法 → nil；
    /// - 只统计两次都存在的 pid（新进程本帧没有基线，不参与 CPU% 排名）；
    /// - 累计值倒退的进程跳过（不产生负百分比）；
    /// - 榜单按降序取前 limit 个；limit ≤ 0 → 空数组。
    public static func processTopN(previous: [Int32: ProcessCPUTimeBaseline]?,
                                   current: [Int32: ProcessCPUTimeBaseline],
                                   names: [Int32: String],
                                   nanosecondsPerTick: Double,
                                   elapsedSeconds: TimeInterval,
                                   limit: Int = 5) -> (cpu: [ProcessResourceUsage],
                                                       memory: [ProcessResourceUsage],
                                                       scanned: Int)? {
        guard let previous, !current.isEmpty else { return nil }
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return nil }
        guard limit > 0 else { return ([], [], 0) }

        var rows: [ProcessResourceUsage] = []
        rows.reserveCapacity(current.count)
        for (pid, now) in current {
            guard let before = previous[pid] else { continue }
            guard let percent = cpuPercent(previousTicks: before.cpuTicks,
                                           currentTicks: now.cpuTicks,
                                           nanosecondsPerTick: nanosecondsPerTick,
                                           elapsedSeconds: elapsedSeconds) else { continue }
            rows.append(ProcessResourceUsage(pid: pid,
                                             name: names[pid] ?? "",
                                             cpuPercent: percent,
                                             residentBytes: now.residentBytes))
        }
        // 全部 pid 都无基线（如系统刚重启后进程全换）→ 与首帧同口径，返回 nil
        guard !rows.isEmpty else { return nil }

        let byCPU = Array(rows.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
        let byMemory = Array(rows.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit))
        return (byCPU, byMemory, current.count)
    }

    // MARK: 功耗

    /// 能量累加器差分换算功率（瓦）
    ///
    /// - nanosecondsPerSecond：Energy Model 的 GPU Energy 单位是 **nJ**，
    ///   故除以 1e9 得焦耳；其它单位（uJ / mJ）由调用方换算成纳焦耳后传入，
    ///   单位一律读通道自带 label，禁止硬编码（同组混着 uJ/nJ/mJ）；
    /// - elapsedSeconds ≤ 0 或非有限 → nil（不除零）；
    /// - 能量倒退（计数器重置）→ nil，不返回负功率；
    /// - 结果按 0...1000 W 合理性过滤：越界视为通道异常，不展示荒谬读数。
    public static func wattsFromEnergyDelta(nanojoules: UInt64,
                                            elapsedSeconds: TimeInterval) -> Double? {
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return nil }
        let joules = Double(nanojoules) / 1_000_000_000
        let watts = joules / elapsedSeconds
        guard watts.isFinite, watts >= 0, watts <= 1_000 else { return nil }
        return watts
    }

    /// 累计能量差；倒退按 0 处理
    public static func energyDelta(previous: UInt64, current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}
