import Darwin
import Foundation
import NetworkMonitorCore

// MARK: - 温度读取（私有 API，独立文件隔离）

/// 通过 IOHIDEventSystemClient 读取 SoC 温度
///
/// 为什么单文件：私有符号只允许出现在 NetworkMonitor（可执行目标），Core 不 import；
/// 也不允许被 UI 直接引用。任何环节失败（dlopen 失败、符号缺失、无传感器、非 Apple Silicon）
/// 一律返回 nil，不 crash、不强制解包。
///
/// 实测（macOS 27 / M1 Pro）：64 个温度服务，全量读取每次约 64ms（1 秒周期占 6.4% CPU）；
/// 初始化（Create + SetMatching + CopyServices + 名字缓存）约 7.8ms 且只做一次，
/// 之后只读 2-4 个关键传感器，每次 < 3ms。因此这里缓存 client 与传感器列表，按名筛选。
///
/// 线程模型：状态（dlopen 句柄、client、传感器指针）只允许在采样串行队列访问，
/// 因此标 @unchecked Sendable；不得在多个队列间共享本实例。
final class SystemThermalReader: @unchecked Sendable {

    // MARK: 私有符号签名

    private typealias CreateFunction = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SetMatchingFunction = @convention(c) (OpaquePointer?, CFDictionary?) -> Void
    private typealias CopyServicesFunction = @convention(c) (OpaquePointer?) -> CFArray?
    private typealias CopyPropertyFunction = @convention(c) (OpaquePointer?, CFString?) -> UnsafeRawPointer?
    private typealias CopyEventFunction = @convention(c) (OpaquePointer?, Int32, Int64, Int64) -> OpaquePointer?
    private typealias GetFloatFunction = @convention(c) (OpaquePointer?, Int64) -> Double

    /// 初始化成功后缓存的可复用会话
    private struct Session {
        let sensors: [(name: String, service: OpaquePointer)]
        let copyEvent: CopyEventFunction
        let getFloatValue: GetFloatFunction
    }

    private enum State {
        case unavailable
        case ready(Session)
    }

    /// kIOHIDEventTypeTemperature = 15（公开枚举，避免为此引入私有头文件）
    private static let temperatureEventType: Int32 = 15
    /// kIOHIDEventFieldTemperatureLevel = 15 << 16
    private static let temperatureLevelField: Int64 = 15 << 16
    /// 合理温度区间（摄氏度）：越界一律丢弃，避免把无效读数当传感器故障以外的值展示
    private static let validRange: ClosedRange<Double> = -20...150

    /// 懒初始化状态；重复失败不再重试（避免每秒重复 dlopen）
    private var state: State?

    // MARK: - 读取

    /// 读取一次温度；不可用或全部传感器读取失败时返回 nil
    func read() -> ThermalSnapshot? {
        let session: Session
        switch ensureSession() {
        case .unavailable:
            return nil
        case .ready(let ready):
            session = ready
        }

        var maxTemperature: Double?
        for sensor in session.sensors {
            guard let event = session.copyEvent(sensor.service,
                                                Self.temperatureEventType, 0, 0) else { continue }
            let celsius = session.getFloatValue(event, Self.temperatureLevelField)
            guard celsius.isFinite, Self.validRange.contains(celsius) else { continue }
            if let current = maxTemperature {
                maxTemperature = max(current, celsius)
            } else {
                maxTemperature = celsius
            }
        }
        guard let cpuTemperature = maxTemperature else { return nil }
        // GPU 温度与 SoC 温度在本机共用传感器，无独立可靠来源 → 保持 nil
        return ThermalSnapshot(cpuTemperatureCelsius: cpuTemperature)
    }

    // MARK: - 初始化

    private func ensureSession() -> State {
        if let state { return state }
        let created = Self.makeSession()
        state = created
        return created
    }

    private static func makeSession() -> State {
        guard let handle = openIOKit() else { return .unavailable }
        guard let create = symbol(handle, "IOHIDEventSystemClientCreate", as: CreateFunction.self),
              let setMatching = symbol(handle, "IOHIDEventSystemClientSetMatching", as: SetMatchingFunction.self),
              let copyServices = symbol(handle, "IOHIDEventSystemClientCopyServices", as: CopyServicesFunction.self),
              let copyProperty = symbol(handle, "IOHIDServiceClientCopyProperty", as: CopyPropertyFunction.self),
              let copyEvent = symbol(handle, "IOHIDServiceClientCopyEvent", as: CopyEventFunction.self),
              let getFloatValue = symbol(handle, "IOHIDEventGetFloatValue", as: GetFloatFunction.self) else {
            return .unavailable
        }
        guard let client = create(kCFAllocatorDefault) else { return .unavailable }

        let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        setMatching(client, matching as CFDictionary)
        guard let services = copyServices(client) else { return .unavailable }

        var cached: [(name: String, service: OpaquePointer)] = []
        for index in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = OpaquePointer(raw)
            cached.append((sensorName(service, copyProperty: copyProperty), service))
        }
        let selected = selectedSensors(from: cached)
        guard !selected.isEmpty else { return .unavailable }
        return .ready(Session(sensors: selected, copyEvent: copyEvent, getFloatValue: getFloatValue))
    }

    /// dlopen IOKit（系统路径优先，其次可能的重定向路径）
    private static func openIOKit() -> UnsafeMutableRawPointer? {
        let versioned = "/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit"
        let plain = "/System/Library/Frameworks/IOKit.framework/IOKit"
        return dlopen(versioned, RTLD_NOW) ?? dlopen(plain, RTLD_NOW)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// 传感器名字（IOHIDServiceClientCopyProperty "Product"）
    private static func sensorName(_ service: OpaquePointer,
                                   copyProperty: CopyPropertyFunction) -> String {
        guard let raw = copyProperty(service, "Product" as CFString) else { return "" }
        let value = unsafeBitCast(raw, to: CFTypeRef.self)
        return (value as? String) ?? ""
    }

    /// 只保留 2-4 个 SoC 温度传感器：PMU tdie 优先生效，其次 TP0s/TP1s 之类
    ///
    /// 实测名字形如 "PMU tdie2"、"PMU TP0s"；名字不匹配时退化为前 2 个 PMU 传感器，
    /// 完全没有 PMU 传感器（非 Apple Silicon / 旧系统）→ 空，读取器整体不可用。
    private static func selectedSensors(from cached: [(name: String, service: OpaquePointer)])
        -> [(name: String, service: OpaquePointer)] {
        let pmu = cached.filter { $0.name.hasPrefix("PMU") }
        guard !pmu.isEmpty else { return [] }
        let dies = pmu.filter { $0.name.lowercased().contains("tdie") }.prefix(2)
        let others = pmu.filter { !$0.name.lowercased().contains("tdie") }.prefix(2)
        let selected = Array(dies) + Array(others)
        return selected.isEmpty ? Array(pmu.prefix(2)) : selected
    }
}
