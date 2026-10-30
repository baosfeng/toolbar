import Foundation
import NetworkMonitorCore

// MARK: - 慢节拍指标采集（拆出主文件）
//
// 拆出原因：主文件负责调度与 1 秒档指标，本文件负责 5 秒档的四项
// （负载 / 进程 Top-N / GPU 功耗 / 电池），两者职责独立，拆开后都远离 15 KiB 门禁。
//
// **只有一个定时器**：「5 秒档」不是另起 Timer，而是由 SystemMonitor.poll() 按
// 上次慢采时间判断是否本帧顺带采集。采集仍跑在同一个后台串行队列上。

// MARK: - 慢节拍中间值类型

/// 慢节拍差分基线
///
/// 跨队列只传值类型：进程基线在高频帧之间保持不变，慢采时才更新。
struct SlowMetricBaselines: Sendable {
    /// 上次慢采的进程累计 ticks（nil = 首帧）
    var processTicks: [Int32: ProcessCPUTimeBaseline]?
    /// 上次慢采的进程名（进程名基本不变，复用省系统调用）
    var processNames: [Int32: String] = [:]
}

/// 一帧慢节拍采集结果
struct SlowMetricResult: Sendable {
    let load: LoadSnapshot?
    let processes: ProcessResourceSnapshot?
    let battery: BatterySnapshot?
    /// GPU 功耗（瓦）；首帧或 IOReport 不可用为 nil
    let gpuPowerWatts: Double?
    let nextBaselines: SlowMetricBaselines
    let failures: [String]
    let issues: [String]
}

// MARK: - 慢节拍采集

extension SystemMonitor {

    /// 慢节拍间隔（秒）：负载其实很便宜，但进程全量与 IOReport 没必要 1 秒一跑
    static let slowSampleInterval: TimeInterval = 5

    /// 是否该在本帧做慢采
    ///
    /// - 首帧（从未慢采）→ true，尽早建立进程基线；
    /// - 之后按「距上次慢采 ≥ slowSampleInterval」判断。
    static func shouldRunSlowSample(now: Date, lastSlowDate: Date?) -> Bool {
        guard let lastSlowDate else { return true }
        return now.timeIntervalSince(lastSlowDate) >= slowSampleInterval
    }

    /// 在后台串行队列上执行一次慢节拍采集
    ///
    /// - Parameters:
    ///   - baselines: 上次的差分基线
    ///   - elapsed: 距上次慢采的墙钟秒数（首帧为 0）
    ///   - powerReader: GPU 功耗读取器（仅后台队列访问）
    /// - Returns: 本帧结果与下一帧基线
    /// nonisolated static：纯函数式，只依赖入参，在后台队列调用不触碰任何 @MainActor 状态
    nonisolated static func collectSlowMetrics(baselines: SlowMetricBaselines,
                                               elapsed: TimeInterval,
                                               powerReader: SystemGPUPowerReader) -> SlowMetricResult {
        var failures: [String] = []
        var issues: [String] = []

        // 负载：getloadavg 几乎免费，失败说明内核接口异常
        let load = SystemLoadSampler.snapshot()
        if load.value == nil { failures.append("系统负载读取失败") }
        issues.append(contentsOf: load.issues)

        // 进程：首帧只建基线（无基线算不出 CPU%），不算失败
        var nextBaselines = baselines
        let currentScan = SystemProcessSampler.scan()
        var processes: ProcessResourceSnapshot?
        if let currentScan {
            let top = SystemMetricsSupplementCalculations.processTopN(
                previous: baselines.processTicks,
                current: currentScan.baselines,
                names: currentScan.names,
                nanosecondsPerTick: SystemProcessSampler.nanosecondsPerTick,
                elapsedSeconds: elapsed)
            if let top {
                processes = ProcessResourceSnapshot(topCPU: top.cpu,
                                                    topMemory: top.memory,
                                                    scannedCount: top.scanned)
            } else if baselines.processTicks != nil {
                failures.append("进程 CPU 差分失败")
            }
            nextBaselines.processTicks = currentScan.baselines
            nextBaselines.processNames = currentScan.names
        } else {
            failures.append("进程列表读取失败")
        }

        // GPU 功耗：私有 IOReport，不可用不算故障（首帧也是 nil）
        let gpuPower = powerReader.read(elapsed: elapsed)

        // 电池：无电池机型（台式机）不算故障，只在读不到时静默降级
        let battery = SystemBatterySampler.snapshot()

        return SlowMetricResult(load: load.value,
                                processes: processes,
                                battery: battery,
                                gpuPowerWatts: gpuPower,
                                nextBaselines: nextBaselines,
                                failures: failures,
                                issues: issues)
    }
}
