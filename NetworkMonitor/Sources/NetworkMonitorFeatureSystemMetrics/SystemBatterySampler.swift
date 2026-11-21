import Foundation
import IOKit
import IOKit.ps
import NetworkMonitorCore

// MARK: - 电池与电源采样

/// 电池采样 — IOPS 电源快照 + AppleSmartBattery 属性 + 外接适配器
///
/// 实测成本 1.44 ms（IOPSGetPowerSourceDescription 占大头）→ 5 秒一次。
///
/// 坑位（实测 macOS 27 / M1 Pro，见第二批指标调研 §2.4）：
/// - TimeRemaining 在 AC 接入时是 **65535 哨兵值**，Amperage = 0 同理，都要过滤，
///   否则会显示「剩余 18 小时」；
/// - IOPSGetTimeRemainingEstimate 返回 -2 (unlimited) 表示 AC 供电，不是错误；
/// - **电池健康度百分比严格不可得**：51 个属性里既无 BatteryHealth 也无 DesignCapacity，
///   只有 CycleCount 与 DesignCycleCount，因此本采样器不产生健康度字段；
/// - IOPS 的 "Max Capacity" 是百分比不是 mAh，别当容量。
enum SystemBatterySampler {

    /// 采样一次电池 + 适配器
    ///
    /// - Returns: 全部不可得时返回 nil（台式机 / 读取失败），不返回空结构体。
    static func snapshot() -> BatterySnapshot? {
        let power = powerSourceInfo()
        let result = BatterySnapshot(percentage: power?.percentage,
                                     isCharging: power?.isCharging,
                                     isOnAC: power?.isOnAC,
                                     cycleCount: cycleCount(),
                                     adapterWatts: externalAdapterWatts())
        // 无电池机型（台式机）：全部字段为 nil → 整体不可用
        return result.isEmpty ? nil : result
    }

    // MARK: IOPS 电源快照

    /// 从 IOPSGetPowerSourceDescription 取电量 / 充电 / 交流
    private static func powerSourceInfo() -> (percentage: Double?, isCharging: Bool?, isOnAC: Bool?)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard let isPresent = description[kIOPSIsPresentKey] as? Bool, isPresent else { continue }
            return (percentage: percentage(from: description),
                    isCharging: description[kIOPSIsChargingKey] as? Bool,
                    isOnAC: isOnAC(description))
        }
        return nil
    }

    /// 电量比例：Current Capacity / Max Capacity（两者都是百分比，实测 80 / 100）
    private static func percentage(from description: [String: Any]) -> Double? {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else {
            return nil
        }
        return min(max(Double(current) / Double(maximum), 0), 1)
    }

    /// 是否接交流电："Power Source State" == "AC Power"
    private static func isOnAC(_ description: [String: Any]) -> Bool? {
        guard let state = description[kIOPSPowerSourceStateKey] as? String else { return nil }
        return state == kIOPSACPowerValue
    }

    // MARK: AppleSmartBattery

    /// 读循环次数（唯一的健康相关可得字段）
    ///
    /// 缺键（非智能电池 / 台式机）返回 nil 而不是 0：0 次循环是有效读数，
    /// 不能与「读不到」混为一谈。
    private static func cycleCount() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleSmartBattery"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        var propertiesRaw: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &propertiesRaw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = propertiesRaw?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return (properties["CycleCount"] as? NSNumber)?.intValue
    }

    // MARK: 外接适配器

    /// 适配器标称功率（瓦）；未接外接电源时为 nil
    ///
    /// 实测本机："Watts" = 94、"Name" = "96W USB-C Power Adapter"。
    /// 注意 Watts 是**标称值不是实时功耗**，UI 只能标注「适配器」不能当充电功率。
    private static func externalAdapterWatts() -> Double? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        guard let watts = (details["Watts"] as? NSNumber)?.doubleValue, watts > 0 else { return nil }
        return watts
    }
}
