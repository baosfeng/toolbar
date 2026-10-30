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
/// 差分类指标（CPU 利用率、磁盘速率）首帧只建基线：字段留 nil 而不是 0，
/// 避免面板把「还没测」显示成「完全不忙」。
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
    /// P/E 核数（启动时读一次，运行期不会变）
    private let coreCounts: (performance: Int, efficiency: Int)

    // MARK: - 差分基线（主线程持有，值类型跨队列传递）

    private var cpuBaseline: CPUTickBaseline?
    private var diskBaseline: DiskTransferTable?
    private var lastSampleDate: Date?
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
                let rates = SystemDiskSampler.rates(previous: previousDiskBaseline,
                                                    current: currentTransfers ?? [:],
                                                    elapsed: elapsed)
                disk = DiskSnapshot(used: capacity.used,
                                    total: capacity.total,
                                    readBytesPerSecond: rates?.read,
                                    writeBytesPerSecond: rates?.write)
            } else {
                disk = nil
                failures.append("磁盘容量读取失败")
            }

            // GPU：首个样本丢弃（预热），第二帧起才可信；无此键不算故障
            let gpu = SystemGPUSampler.snapshot(isWarm: isGPUBaselineReady)

            // 温度：私有 API 尽力而为，不可用不算故障（不回退，不重试）
            let thermal = reader.read()

            let sampledAt = Date()
            let nextSnapshot = SystemMetricsSnapshot(timestamp: sampledAt,
                                                     cpu: cpu,
                                                     gpu: gpu,
                                                     memory: memory.value,
                                                     disk: disk,
                                                     thermal: thermal)
            let nextCPUBaseline = currentTicks.map { CPUTickBaseline(ticks: $0) }
            let nextDiskBaseline = currentTransfers

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSampling = false
                self.snapshot = nextSnapshot
                self.cpuBaseline = nextCPUBaseline
                self.diskBaseline = nextDiskBaseline
                self.lastSampleDate = sampledAt
                self.hasGPUBaseline = true
                self.report(failures: failures, issues: issues)
            }
        }
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
