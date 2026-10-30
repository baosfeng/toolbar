import Foundation
import IOKit
import NetworkMonitorCore

// MARK: - GPU 采样

/// GPU 采样 — IOAccelerator 的 PerformanceStatistics 字典
///
/// 键名实测（macOS 27 / M1 Pro，加速器类名 AGXAcceleratorG13X）：
/// - "Device Utilization %" 0-100 整数，空闲 0%、Metal 负载下 94-100%，以此为准；
/// - "Renderer Utilization %" / "Tiler Utilization %" 抖动大（实测 12-71%），不采用；
/// - "In use system memory" 字节数（可选，集成 GPU 无独立显存，memoryTotal 保持 nil）。
///
/// 可用性判断看「键是否存在」而不是数值：冷读可能返回 0%（不是没读到）。
/// 键不存在（无 GPU / 驱动不暴露统计）→ 整体 nil。
enum SystemGPUSampler {

    /// - Parameter isWarm: 是否已过预热首帧（false 时一律 nil，冷读的 0% 不可信）
    static func snapshot(isWarm: Bool) -> GPUSnapshot? {
        guard let statistics = performanceStatistics(),
              let utilization = SystemMetricsCalculations.gpuUtilization(statistics: statistics,
                                                                         isWarm: isWarm) else {
            return nil
        }
        let memoryUsed = (statistics["In use system memory"] as? NSNumber)?.uint64Value
        return GPUSnapshot(utilization: utilization, memoryUsed: memoryUsed, memoryTotal: nil)
    }

    /// 取第一个 IOAccelerator 实例的 PerformanceStatistics
    private static func performanceStatistics() -> [String: Any]? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                  IOServiceMatching("IOAccelerator"),
                                                  &iterator)
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        guard let property = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString,
                                                             kCFAllocatorDefault, 0) else {
            return nil
        }
        return property.takeRetainedValue() as? [String: Any]
    }
}
