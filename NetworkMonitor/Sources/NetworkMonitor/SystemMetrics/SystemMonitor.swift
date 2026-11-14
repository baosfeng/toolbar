import Foundation
import NetworkMonitorCore

// MARK: - 系统指标采样服务

/// 系统指标采样 — 周期采集 CPU / GPU / 内存 / 磁盘 / 温度
///
/// 线程模型（对齐项目既有范式）：
/// - 本类 @MainActor，poll() 在主线程只做状态取值与排队；
/// - 实际系统调用在后台串行队列执行（sysctl / Mach / IOKit 均不阻塞主线程）；
/// - 采集完成后 Task { @MainActor } 回写 snapshot 与新基线；
/// - 跨队列只传值类型（CPUTickBaseline / DiskTransferTable / SystemMetricsSnapshot），
///   不共享可变对象，也不让 @MainActor 实例逃逸。
///
/// 差分类指标（CPU 利用率、磁盘速率 / IOPS / 繁忙度、进程 CPU%）首帧只建基线：
/// 字段留 nil 而不是 0，避免面板把「还没测」显示成「完全不忙」。
///
/// 只有一个定时器：负载 / 进程 Top-N / GPU 功耗 / 电池属「5 秒档」，
/// 由 poll() 按上次慢采时间判断是否本帧顺带采集（见 SystemMonitor+SlowMetrics.swift）。
@MainActor
final class SystemMonitor: @preconcurrency SystemMonitoringService {

    // MARK: - 对外状态

    private(set) var snapshot: SystemMetricsSnapshot?

    // MARK: - 依赖与配置

    private let interval: TimeInterval
    private let logger: any LoggingService
    /// 后台采集串行队列
    private let queue = DispatchQueue(label: "com.networkmonitor.system-metrics", qos: .utility)
    /// 温度读取器：内部缓存 IOHID client，只允许后台串行队列访问
    private let thermalReader = SystemThermalReader()
    /// GPU 功耗读取器：内部缓存 IOReport subscription，只允许后台串行队列访问
    private let powerReader = SystemGPUPowerReader()
    /// P/E 核数（启动时读一次，运行期不会变）
    private let coreCounts: (performance: Int, efficiency: Int)

    // MARK: - 差分基线（主线程持有，值类型跨队列传递）

    private var cpuBaseline: CPUTickBaseline?
    private var diskBaseline: DiskTransferTable?
    private var lastSampleDate: Date?
    /// 慢节拍（5 秒档）基线
    private var slowBaselines = SlowMetricBaselines()
    /// 上次慢采时刻；nil 表示还没采过（首帧必采）
    private var lastSlowSampleDate: Date?
    /// GPU 首个样本丢弃：冷读可能返回 0%（不是没读到），第二帧起数值才可信
    private var hasGPUBaseline = false

    // MARK: - 调度状态

    private var timer: Timer?
    private var isSampling = false
    /// 已告警过的失败项：同一项只 warning 一次，之后 debug，避免每秒刷屏
    private var reportedFailures: Set<String> = []

    // MARK: - 初始化

    init(interval: TimeInterval = SystemMonitorPreferences.defaultSampleInterval,
         logger: any LoggingService = AppContext.shared.logger) {
        self.interval = max(interval, SystemMonitorPreferences.minimumSampleInterval)
        self.logger = logger
        self.coreCounts = SystemCPUSampler.coreCounts()
    }

    // MARK: - 生命周期

    /// 启动定时采样并立即采一帧（首帧只建基线，CPU / 磁盘速率为 nil）
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        // .common：菜单面板弹出（eventTracking）时仍能触发
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    /// 停止定时采样（定时器必须显式停止，否则会一直挂在 RunLoop 上）
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 采样

    func poll() {
        guard !isSampling else { return }
        isSampling = true

        let sampleStart = Date()
        let elapsed = lastSampleDate.map { sampleStart.timeIntervalSince($0) } ?? 0
        let previousCPUBaseline = cpuBaseline
        let previousDiskBaseline = diskBaseline
        let counts = coreCounts
        let isGPUBaselineReady = hasGPUBaseline
        let reader = thermalReader
        let powerReader = self.powerReader
        // 慢节拍判定在主线程做：5 秒档不是新 Timer，而是本帧顺手多采一组
        let runsSlowSample = Self.shouldRunSlowSample(now: sampleStart, lastSlowDate: lastSlowSampleDate)
        let slowBaselines = self.slowBaselines
        let previousSlowDate = lastSlowSampleDate
        let slowElapsed = previousSlowDate.map { sampleStart.timeIntervalSince($0) } ?? 0
        // 上帧的慢节拍结果：本帧不采慢节拍时沿用它，避免面板每 5 秒才亮一次
        let carriedLoad = snapshot?.load
        let carriedProcesses = snapshot?.processes
        let carriedBattery = snapshot?.battery
        let carriedWiFi = snapshot?.wifi
        let carriedPower = snapshot?.thermal?.powerWatts

        queue.async { [weak self] in
            var failures: [String] = []
            var issues: [String] = []

            // CPU：两次 tick 差分；首帧（无基线）不算失败，只建基线
            let currentTicks = SystemCPUSampler.readTicks()
            let cpu: CPUSnapshot?
            if let ticks = currentTicks {
                cpu = SystemCPUSampler.snapshot(previous: previousCPUBaseline,
                                                current: ticks,
                                                coreCounts: counts)
                if cpu == nil, previousCPUBaseline != nil {
                    failures.append("CPU 利用率差分失败")
                }
            } else {
                cpu = nil
                failures.append("CPU tick 读取失败")
            }

            // 内存：整项不可用才算失败；压力回退记 issue
            let memory = SystemMemorySampler.snapshot()
            if memory.value == nil {
                failures.append("内存统计读取失败")
            }
            issues.append(contentsOf: memory.issues)

            // 磁盘：容量决定字段是否可用；速率无基线时留 nil
            let capacity = SystemDiskSampler.capacity()
            let currentTransfers = SystemDiskSampler.transfers()
            if currentTransfers == nil {
                failures.append("磁盘 IO 统计读取失败")
            }
            let disk: DiskSnapshot?
            if let capacity {
                // 速率 / IOPS / 繁忙度共用同一个 elapsed：三项必须同源，否则互相不可比
                let throughput = SystemDiskSampler.throughput(previous: previousDiskBaseline,
                                                              current: currentTransfers ?? [:],
                                                              elapsed: elapsed)
                disk = DiskSnapshot(used: capacity.used,
                                    total: capacity.total,
                                    readBytesPerSecond: throughput?.readBytesPerSecond,
                                    writeBytesPerSecond: throughput?.writeBytesPerSecond,
                                    readIOPS: throughput?.readIOPS,
                                    writeIOPS: throughput?.writeIOPS,
                                    busyFraction: throughput?.busyFraction)
            } else {
                disk = nil
                failures.append("磁盘容量读取失败")
            }

            // GPU：首个样本丢弃（预热），第二帧起才可信；无此键不算故障
            let gpu = SystemGPUSampler.snapshot(isWarm: isGPUBaselineReady)

            // 温度：私有 API 尽力而为，不可用不算故障（不回退，不重试）
            let thermalReading = reader.read()

            // 慢节拍（5 秒档）：只在到点的那一帧采，其余帧沿用上一帧结果
            let slowResult = runsSlowSample
                ? Self.collectSlowMetrics(baselines: slowBaselines,
                                          elapsed: slowElapsed,
                                          powerReader: powerReader)
                : nil
            failures.append(contentsOf: slowResult?.failures ?? [])
            issues.append(contentsOf: slowResult?.issues ?? [])

            // GPU 功耗写进温度快照的 powerWatts（语义已改为 GPU 功耗，非整机）
            let powerWatts = slowResult.map { $0.gpuPowerWatts } ?? carriedPower
            let thermal = Self.merging(thermal: thermalReading, powerWatts: powerWatts)

            let sampledAt = Date()
            let nextSnapshot = SystemMetricsSnapshot(timestamp: sampledAt,
                                                     cpu: cpu,
                                                     gpu: gpu,
                                                     memory: memory.value,
                                                     disk: disk,
                                                     thermal: thermal,
                                                     load: slowResult?.load ?? carriedLoad,
                                                     processes: slowResult?.processes ?? carriedProcesses,
                                                     battery: slowResult?.battery ?? carriedBattery,
                                                     // Wi-Fi 用 map 而不是 ??：慢采到点时必须用本帧结果，
                                                     // 断网 / Wi-Fi 关闭要让链路指标真的消失，不能沿用旧值
                                                     wifi: slowResult.map { $0.wifi } ?? carriedWiFi)
            let nextCPUBaseline = currentTicks.map { CPUTickBaseline(ticks: $0) }
            let nextDiskBaseline = currentTransfers
            let nextSlowBaselines = slowResult?.nextBaselines ?? slowBaselines
            let nextSlowDate = slowResult == nil ? previousSlowDate : sampledAt

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSampling = false
                self.snapshot = nextSnapshot
                self.cpuBaseline = nextCPUBaseline
                self.diskBaseline = nextDiskBaseline
                self.slowBaselines = nextSlowBaselines
                self.lastSampleDate = sampledAt
                self.lastSlowSampleDate = nextSlowDate
                self.hasGPUBaseline = true
                self.report(failures: failures, issues: issues)
            }
        }
    }

    // MARK: - 快照合并

    /// 把 GPU 功耗并进温度快照
    ///
    /// 温度为 nil 但功耗有值时也要产出一个只含功耗的快照，否则面板会把已采到的
    /// 功耗一并显示成「—」。功耗为 nil 时原样返回温度读数（可能也是 nil）。
    private nonisolated static func merging(thermal: ThermalSnapshot?, powerWatts: Double?) -> ThermalSnapshot? {
        guard let powerWatts else { return thermal }
        guard let thermal else { return ThermalSnapshot(powerWatts: powerWatts) }
        return ThermalSnapshot(cpuTemperatureCelsius: thermal.cpuTemperatureCelsius,
                               gpuTemperatureCelsius: thermal.gpuTemperatureCelsius,
                               powerWatts: powerWatts,
                               fanRPM: thermal.fanRPM)
    }

    // MARK: - 日志

    /// 记录降级：同一失败项只 warning 一次，之后降为 debug
    private func report(failures: [String], issues: [String]) {
        for failure in failures where !reportedFailures.contains(failure) {
            reportedFailures.insert(failure)
            logger.warning("系统指标采样降级：\(failure)")
        }
        for issue in issues where !reportedFailures.contains(issue) {
            reportedFailures.insert(issue)
            logger.debug("系统指标采样提示：\(issue)")
        }
    }
}
