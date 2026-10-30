import Darwin
import Foundation
import NetworkMonitorCore

// MARK: - CPU 采样

/// CPU 采样 — host_processor_info 差分，配合 sysctl 取 P/E 核数
///
/// 口径：每核利用率 = (user + system + nice) / (user + system + idle + nice) 的增量比；
/// 总利用率 = 所有核忙时增量之和 / 所有核全部增量之和（与主机 HOST_CPU_LOAD_INFO 口径一致，实测差 < 0.3pp）。
enum SystemCPUSampler {

    /// 读取每核累计 tick（每核 4 个槽位，顺序同 CPU_STATE_* 常量）
    static func readTicks() -> [UInt32]? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS, let infoArray else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: infoArray)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let slotCount = Int(cpuCount) * Int(CPU_STATE_MAX)
        guard slotCount > 0, Int(infoCount) >= slotCount else { return nil }
        var ticks = [UInt32]()
        ticks.reserveCapacity(slotCount)
        for index in 0..<slotCount {
            ticks.append(UInt32(bitPattern: infoArray[index]))
        }
        return ticks
    }

    /// 由两次 tick 采样算快照
    ///
    /// 差分与边界口径全部由 Core 的 SystemMetricsCalculations.cpuUsage 承担（可测试），
    /// 这里只做「基线缺失 → nil」的判断与快照封装。
    static func snapshot(previous: CPUTickBaseline?, current: [UInt32],
                         coreCounts: (performance: Int, efficiency: Int)) -> CPUSnapshot? {
        guard let baseline = previous,
              let sample = SystemMetricsCalculations.cpuUsage(previous: baseline.ticks,
                                                              current: current) else {
            return nil
        }
        return CPUSnapshot(totalUsage: sample.totalUsage,
                           perCore: sample.perCore,
                           performanceCores: coreCounts.performance,
                           efficiencyCores: coreCounts.efficiency,
                           userUsage: sample.userUsage,
                           systemUsage: sample.systemUsage)
    }

    /// P/E 核数量
    ///
    /// 注意：perCore 的下标顺序实测为 E 核在前（逻辑 CPU 0、1）、P 核在后（2…9），
    /// 分组切片统一走 SystemMetricsFormatting.splitCores，本函数只负责数量。
    ///
    /// 键名实测（macOS 27 / Apple M1 Pro）：
    /// - hw.perflevel0.name = "Performance"，hw.perflevel0.physicalcpu = 8
    /// - hw.perflevel1.name = "Efficiency"，hw.perflevel1.physicalcpu = 2
    /// 取不到（Intel 或旧系统）时返回 (0, 0)，perCore 照常返回，调用方按「未分组」处理。
    static func coreCounts() -> (performance: Int, efficiency: Int) {
        let performance = Int(sysctlInt32("hw.perflevel0.physicalcpu") ?? 0)
        let efficiency = Int(sysctlInt32("hw.perflevel1.physicalcpu") ?? 0)
        return (max(performance, 0), max(efficiency, 0))
    }
}
