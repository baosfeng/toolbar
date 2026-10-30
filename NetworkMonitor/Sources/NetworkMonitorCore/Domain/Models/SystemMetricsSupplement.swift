import Foundation

// MARK: - 第二批 P0 指标快照（负载 / 进程 / 电池）
//
// 独立成文件的理由：SystemMetrics.swift 已承载 CPU / GPU / 内存 / 磁盘 / 温度五组模型，
// 再塞入第二批三组会把单文件推近 15360 字节门禁；三组指标与第一批互不依赖，
// 按 SRP 分文件，SystemMetricsSnapshot 只持有它们的可选字段。

// MARK: - 负载与调度状态

/// 热压力等级（对齐 ProcessInfo.ThermalState，但 Core 不直接依赖该类型）
///
/// 原始枚举值：0 nominal / 1 fair / 2 serious / 3 critical；
/// 未来系统新增档位时按 unknown 处理，不猜。
public enum ThermalStateLevel: String, Sendable {
    /// 正常
    case nominal
    /// 轻微（系统开始降频调度）
    case fair
    /// 严重（明显降频）
    case serious
    /// 临界（可能触发强制散热限制）
    case critical
    /// 未知 / 系统新增档位
    case unknown
}

/// 系统负载与调度状态采样结果
///
/// 负载是「就绪队列长度」而不是 CPU 占用百分比：load 持续大于核数说明有进程在排队。
/// 三个窗口（1 / 5 / 15 分钟）由内核按指数衰减维护，采样成本约 0.0068 ms。
public struct LoadSnapshot: Sendable, Equatable {
    /// 1 分钟平均负载（原始值，未归一化）
    public let load1: Double
    /// 5 分钟平均负载
    public let load5: Double
    /// 15 分钟平均负载
    public let load15: Double
    /// 逻辑核数（归一化分母；取不到为 0，调用方按「不归一化」处理）
    public let coreCount: Int
    /// 热压力等级
    public let thermalState: ThermalStateLevel
    /// 低电量模式是否开启（开启时系统会主动降频）
    public let isLowPowerModeEnabled: Bool

    public init(load1: Double,
                load5: Double,
                load15: Double,
                coreCount: Int,
                thermalState: ThermalStateLevel = .unknown,
                isLowPowerModeEnabled: Bool = false) {
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.coreCount = coreCount
        self.thermalState = thermalState
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }
}

// MARK: - 进程资源占用

/// 单个进程的资源占用（Top-N 列表元素）
///
/// cpuPercent 的单位是「单核百分比」：多线程进程合法地超过 100（实测 3 线程自旋 298%），
/// 因此**不 clamp 到 100**，否则 Top-N 排序会被削平。
public struct ProcessResourceUsage: Sendable, Equatable {
    /// 进程 ID
    public let pid: Int32
    /// 进程名（proc_name 取前 255 字节，可能被截断）
    public let name: String
    /// CPU 占用百分比（单核百分比，可 > 100）
    public let cpuPercent: Double
    /// 常驻内存（字节）
    public let residentBytes: UInt64

    public init(pid: Int32, name: String, cpuPercent: Double, residentBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }
}

/// 进程 Top-N 快照
///
/// 两份榜单分开给：CPU% 高的未必占内存多，合并成一份会让两类诉求互相挤掉。
public struct ProcessResourceSnapshot: Sendable, Equatable {
    /// CPU 占用最高的若干进程（按 cpuPercent 降序）
    public let topCPU: [ProcessResourceUsage]
    /// 常驻内存最高的若干进程（按 residentBytes 降序）
    public let topMemory: [ProcessResourceUsage]
    /// 本帧成功读到 taskinfo 的进程数（用于判断采样是否退化）
    public let scannedCount: Int

    public init(topCPU: [ProcessResourceUsage],
                topMemory: [ProcessResourceUsage],
                scannedCount: Int) {
        self.topCPU = topCPU
        self.topMemory = topMemory
        self.scannedCount = scannedCount
    }
}

// MARK: - 电池与电源

/// 电池与电源适配器采样结果
///
/// 全部字段可选：台式机无电池、读不到适配器时对应字段为 nil，不写 0 冒充。
/// **健康度百分比严格不可得**：本机 51 个 AppleSmartBattery 属性里既无 BatteryHealth
/// 也无 DesignCapacity，只有 CycleCount 与 DesignCycleCount，故只能给循环次数。
public struct BatterySnapshot: Sendable, Equatable {
    /// 电量比例（0...1）；不可得为 nil
    public let percentage: Double?
    /// 是否正在充电
    public let isCharging: Bool?
    /// 是否接交流电（外接电源）
    public let isOnAC: Bool?
    /// 电池循环次数
    public let cycleCount: Int?
    /// 外接电源适配器标称功率（瓦）；未接适配器为 nil
    public let adapterWatts: Double?

    public init(percentage: Double? = nil,
                isCharging: Bool? = nil,
                isOnAC: Bool? = nil,
                cycleCount: Int? = nil,
                adapterWatts: Double? = nil) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.cycleCount = cycleCount
        self.adapterWatts = adapterWatts
    }

    /// 是否没有任何可用值
    public var isEmpty: Bool {
        percentage == nil && isCharging == nil && isOnAC == nil
            && cycleCount == nil && adapterWatts == nil
    }
}
