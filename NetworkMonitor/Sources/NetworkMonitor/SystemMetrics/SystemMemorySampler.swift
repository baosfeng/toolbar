import Darwin
import Foundation
import NetworkMonitorCore

// MARK: - 内存采样

/// 内存采样 — host_statistics64 + vm_statistics64，页大小用 host_page_size 动态取
///
/// used 口径：active + wired + compressed
/// - 不含 inactive：可被系统随时回收的页面，计进去会让读数长期偏高；
/// - 不含 free：空闲页；
/// - compressed 单独计：压缩器占用的物理页确实被占用（与活动监视器的「已用内存」口径接近）。
///
/// Apple Silicon 页大小为 16 KiB（本机 16384），Intel 为 4096，因此禁止硬编码。
enum SystemMemorySampler {

    /// 采样一次内存
    ///
    /// - Returns: value 为 nil 表示整项不可用；issues 为可记录的降级说明（不影响 value）。
    static func snapshot() -> (value: MemorySnapshot?, issues: [String]) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (nil, ["host_statistics64 失败（kern_return_t = \(result)）"])
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        guard pageSize > 0 else { return (nil, ["host_page_size 返回 0"]) }
        let pageBytes = UInt64(pageSize)

        let active = UInt64(stats.active_count) &* pageBytes
        let wired = UInt64(stats.wire_count) &* pageBytes
        let compressed = UInt64(stats.compressor_page_count) &* pageBytes
        let used = active &+ wired &+ compressed

        guard let total = sysctlUInt64("hw.memsize"), total > 0 else {
            return (nil, ["hw.memsize 读取失败"])
        }

        var issues: [String] = []
        let pressure: MemoryPressureLevel
        if let level = readPressureLevel() {
            pressure = level
        } else {
            pressure = .normal
            issues.append("内存压力等级不可读，按正常展示")
        }

        let swap = readSwapUsage()
        return (MemorySnapshot(used: used,
                               total: total,
                               pressure: pressure,
                               swapUsed: swap?.used ?? 0,
                               swapTotal: swap?.total ?? 0,
                               compressed: compressed),
                issues)
    }

    /// 读取内存压力等级
    ///
    /// 主键：kern.memorystatus_vm_pressure_level（本机实测可取，1 正常 / 2 警示 / 4 紧张）。
    /// 回退：vm.memory_pressure（0 正常 / 1 警示 / 2 紧张），仅在主键不可读时使用。
    private static func readPressureLevel() -> MemoryPressureLevel? {
        if let raw = sysctlInt32("kern.memorystatus_vm_pressure_level"),
           let level = MemoryPressureLevel(sysctlRawValue: raw) {
            return level
        }
        switch sysctlInt32("vm.memory_pressure") {
        case 0: return .normal
        case 1: return .warning
        case 2: return .critical
        default: return nil
        }
    }

    /// 读取 swap 用量（vm.swapusage）
    private static func readSwapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (usage.xsu_used, usage.xsu_total)
    }
}
