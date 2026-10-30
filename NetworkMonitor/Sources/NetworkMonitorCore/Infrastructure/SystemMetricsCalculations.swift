import Foundation

// MARK: - 系统指标纯计算（差分 / 降级判定）
//
// 采样器落在 NetworkMonitor 目标（AppKit / IOKit 只能在可执行目标），
// TestRunner 只依赖 NetworkMonitorCore，因此把「差分与降级判定」这类纯计算下沉到这里：
// 采样器只负责读原始数据，口径与判定全部由本文件承担，测试直接覆盖。

/// 单帧 CPU 差分结果
public struct CPUUsageSample: Sendable, Equatable {
    /// 每核利用率（0...1），下标与输入的核心顺序一致
    public let perCore: [Double]
    /// 总利用率（所有核 busy / 所有核全部 ticks）
    public let totalUsage: Double
    /// 用户态占比（占全部 ticks）
    public let userUsage: Double
    /// 系统态占比（占全部 ticks）
    public let systemUsage: Double

    public init(perCore: [Double], totalUsage: Double, userUsage: Double, systemUsage: Double) {
        self.perCore = perCore
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
    }
}

// MARK: - CPU

public enum SystemMetricsCalculations {

    /// CPU 差分：由两次每核累计 tick 算利用率
    ///
    /// 入参形态与 host_processor_info(PROCESSOR_CPU_LOAD_INFO) 一致：
    /// 扁平数组，每核 4 个槽位，顺序固定为 [user, system, idle, nice]（即 CPU_STATE_* 顺序）。
    ///
    /// 边界约定：
    /// - 两帧完全相同（零 delta）→ 每核与总量全部为 0，不产生 NaN / Inf；
    /// - 核数变化（如热插拔 / 采样长度不一致）→ 按最小核数截断，多出的核本帧不参与；
    /// - 单个计数倒退（计数器重置）→ 该槽位按 0 处理，不产生负利用率；
    /// - 长度不是 4 的倍数或为空 → nil（数据形态不合法，不猜）。
    public static func cpuUsage(previous: [UInt32], current: [UInt32]) -> CPUUsageSample? {
        let stateCount = 4
        guard !previous.isEmpty, !current.isEmpty,
              previous.count % stateCount == 0, current.count % stateCount == 0 else {
            return nil
        }
        let coreCount = min(previous.count, current.count) / stateCount
        guard coreCount > 0 else { return nil }

        var perCore = [Double]()
        perCore.reserveCapacity(coreCount)
        var totalBusy = 0.0
        var totalAll = 0.0
        var totalUser = 0.0
        var totalSystem = 0.0

        for core in 0..<coreCount {
            let offset = core * stateCount
            let user = delta(previous[offset], current[offset])
            let system = delta(previous[offset + 1], current[offset + 1])
            let idle = delta(previous[offset + 2], current[offset + 2])
            let nice = delta(previous[offset + 3], current[offset + 3])
            let coreBusy = user + system + nice
            let coreAll = coreBusy + idle
            perCore.append(coreAll > 0 ? coreBusy / coreAll : 0)
            totalBusy += coreBusy
            totalAll += coreAll
            totalUser += user
            totalSystem += system
        }

        guard totalAll > 0 else {
            return CPUUsageSample(perCore: [Double](repeating: 0, count: coreCount),
                                  totalUsage: 0, userUsage: 0, systemUsage: 0)
        }
        return CPUUsageSample(perCore: perCore,
                              totalUsage: totalBusy / totalAll,
                              userUsage: totalUser / totalAll,
                              systemUsage: totalSystem / totalAll)
    }

    /// 单个 tick 槽位的增量；倒退按 0 处理（计数器重置 / 异常值）
    private static func delta(_ previous: UInt32, _ current: UInt32) -> Double {
        current >= previous ? Double(current - previous) : 0
    }

    // MARK: GPU

    /// 从 IOAccelerator 的 PerformanceStatistics 解析 GPU 利用率（0...1）
    ///
    /// 入参用 [String: Any] 而不是 IOKit 类型，Core 不引入 IOKit。
    ///
    /// - 预热首帧（isWarm = false）→ nil：冷读可能返回 0%，不代表真实利用率；
    /// - 字典为空或缺 "Device Utilization %" 键 → nil（键不存在才是不可用，数值为 0 是有效读数）；
    /// - 值不是数字或越界（< 0 或 > 100）→ nil（异常数据不夹紧，直接判不可用）。
    public static func gpuUtilization(statistics: [String: Any]?, isWarm: Bool) -> Double? {
        guard isWarm, let statistics else { return nil }
        guard let raw = statistics["Device Utilization %"] as? NSNumber else { return nil }
        let percent = raw.doubleValue
        guard percent.isFinite, percent >= 0, percent <= 100 else { return nil }
        return percent / 100
    }
}
