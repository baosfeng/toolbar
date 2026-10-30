import Darwin
import Foundation
import NetworkMonitorCore

// MARK: - 负载采样

/// 负载与调度状态采样 — getloadavg(3) + ProcessInfo
///
/// getloadavg 实测成本 0.0068 ms，可随 1 秒周期跑。
/// thermalState / isLowPowerModeEnabled 也都是纳秒级读取，一并放这里。
enum SystemLoadSampler {

    /// 采样一次负载
    ///
    /// - Returns: value 为 nil 表示 getloadavg 完全不可用（内核返回 0 个样本）；
    ///   issues 为可记录的降级说明（不影响 value）。
    static func snapshot() -> (value: LoadSnapshot?, issues: [String]) {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        guard count > 0 else {
            return (nil, ["getloadavg 不可用（returned = \(count)）"])
        }
        // 返回的数量可能少于 3（罕见）：缺失窗口按 0 处理而不是给 NaN
        let load1 = count > 0 ? loads[0] : 0
        let load5 = count > 1 ? loads[1] : 0
        let load15 = count > 2 ? loads[2] : 0

        var issues: [String] = []
        if count < 3 {
            issues.append("getloadavg 仅返回 \(count)/3 个窗口，缺失项按 0 展示")
        }
        let processInfo = ProcessInfo.processInfo
        return (LoadSnapshot(load1: load1,
                             load5: load5,
                             load15: load15,
                             coreCount: processInfo.processorCount,
                             thermalState: thermalLevel(processInfo.thermalState),
                             isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled),
                issues)
    }

    /// ProcessInfo.ThermalState → Core 的 ThermalStateLevel
    ///
    /// 未来系统新增档位时回退 unknown，不猜成 nominal。
    private static func thermalLevel(_ state: ProcessInfo.ThermalState) -> ThermalStateLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
