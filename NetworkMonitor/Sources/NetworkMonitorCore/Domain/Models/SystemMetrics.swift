import Foundation

// MARK: - 系统指标快照

/// 一次系统指标采样的完整快照
///
/// 各子领域均为可选：某项采集失败（平台差异、API 不可用、权限限制）时对应字段为 nil，
/// 其余指标照常展示。调用方无需区分「采集失败」与「本机不支持」，统一按 nil 降级。
public struct SystemMetricsSnapshot: Sendable, Equatable {
    /// 采样完成时刻
    public let timestamp: Date
    /// CPU 指标（需要两次采样才能算出利用率，首帧为 nil）
    public let cpu: CPUSnapshot?
    /// GPU 指标（无法读取加速器统计时为 nil）
    public let gpu: GPUSnapshot?
    /// 内存指标（host_statistics64 可用时基本总能取到）
    public let memory: MemorySnapshot?
    /// 磁盘指标（容量取不到时整体为 nil；首帧速率为 nil）
    public let disk: DiskSnapshot?
    /// 温度 / 功耗 / 风扇（全部不可得时为 nil）
    public let thermal: ThermalSnapshot?
    /// 系统负载与调度状态（getloadavg 不可用时为 nil）
    public let load: LoadSnapshot?
    /// 进程 Top-N（首帧无基线、或一个进程都读不到时为 nil）
    public let processes: ProcessResourceSnapshot?
    /// 电池与电源（无电池机型 / 读取失败时为 nil）
    public let battery: BatterySnapshot?
    /// Wi-Fi 链路（无 Wi-Fi 接口 / Wi-Fi 关闭 / 未连接时为 nil，不是 0）
    public let wifi: WiFiLinkSnapshot?

    public init(timestamp: Date = Date(),
                cpu: CPUSnapshot? = nil,
                gpu: GPUSnapshot? = nil,
                memory: MemorySnapshot? = nil,
                disk: DiskSnapshot? = nil,
                thermal: ThermalSnapshot? = nil,
                load: LoadSnapshot? = nil,
                processes: ProcessResourceSnapshot? = nil,
                battery: BatterySnapshot? = nil,
                wifi: WiFiLinkSnapshot? = nil) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.thermal = thermal
        self.load = load
        self.processes = processes
        self.battery = battery
        self.wifi = wifi
    }
}

// MARK: - CPU

/// CPU 采样结果
///
/// 利用率统一用 0...1 的比例表达（UI 层再乘 100 格式化），避免各层口径不一。
public struct CPUSnapshot: Sendable, Equatable {
    /// 总利用率（所有核 busy ticks / 全部 ticks）
    public let totalUsage: Double
    /// 每核利用率，顺序与 Mach 返回的处理器编号一致（实测为 E 核在前、P 核在后）
    public let perCore: [Double]
    /// 性能核（P core）数量；sysctl 取不到时为 0（不代表没有 P 核）
    public let performanceCores: Int
    /// 能效核（E core）数量；sysctl 取不到时为 0
    public let efficiencyCores: Int
    /// 用户态占比（占全部 ticks，含 idle）；不可得为 nil
    public let userUsage: Double?
    /// 系统态占比（占全部 ticks，含 idle）；不可得为 nil
    public let systemUsage: Double?

    public init(totalUsage: Double,
                perCore: [Double],
                performanceCores: Int,
                efficiencyCores: Int,
                userUsage: Double? = nil,
                systemUsage: Double? = nil) {
        self.totalUsage = totalUsage
        self.perCore = perCore
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.userUsage = userUsage
        self.systemUsage = systemUsage
    }
}

// MARK: - GPU

/// GPU 采样结果
///
/// 集成 GPU 与 CPU 共享物理内存，memoryTotal 通常不可得（保持 nil），
/// 只在加速器统计里确实带有独立显存信息时才填。
public struct GPUSnapshot: Sendable, Equatable {
    /// GPU 利用率（0...1）
    public let utilization: Double
    /// 已用显存 / 统一内存（字节）；不可得为 nil
    public let memoryUsed: UInt64?
    /// 显存总量（字节）；不可得为 nil
    public let memoryTotal: UInt64?

    public init(utilization: Double, memoryUsed: UInt64? = nil, memoryTotal: UInt64? = nil) {
        self.utilization = utilization
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
    }
}

// MARK: - 内存

/// 内存压力等级
public enum MemoryPressureLevel: String, Sendable {
    /// 正常
    case normal
    /// 警示（系统开始压缩 / 回收）
    case warning
    /// 紧张（可能触发 swap 与杀进程）
    case critical

    /// 由 kern.memorystatus_vm_pressure_level 的原始值构造
    ///
    /// 系统口径：1 = 正常，2 = 警示，4 = 紧张；其余值（含 0 与未知值）返回 nil，
    /// 由调用方决定回退策略，避免把未知值误判成正常。
    public init?(sysctlRawValue: Int32) {
        switch sysctlRawValue {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }
}

/// 内存采样结果
///
/// 口径：used = active + wired + compressed（不含 inactive / free，注释见采样实现）。
/// active / wired / inactive 为拆分字段，供面板分段展示；inactive 不计入 used，
/// 它是可被系统随时回收的页面，计进去会让读数长期偏高。
public struct MemorySnapshot: Sendable, Equatable {
    /// 已用内存（字节）
    public let used: UInt64
    /// 物理内存总量（字节）
    public let total: UInt64
    /// 内存压力等级
    public let pressure: MemoryPressureLevel
    /// swap 已用（字节）
    public let swapUsed: UInt64
    /// swap 总量（字节；未启用 swap 时为 0）
    public let swapTotal: UInt64
    /// 压缩器占用（字节）
    public let compressed: UInt64
    /// 活跃内存（字节；vm_statistics64 的 active_count）
    public let active: UInt64
    /// 联动内存（字节；vm_statistics64 的 wire_count，不可换出）
    public let wired: UInt64
    /// 非活跃内存（字节；vm_statistics64 的 inactive_count，可被回收，不计入 used）
    public let inactive: UInt64

    public init(used: UInt64,
                total: UInt64,
                pressure: MemoryPressureLevel,
                swapUsed: UInt64,
                swapTotal: UInt64,
                compressed: UInt64,
                active: UInt64 = 0,
                wired: UInt64 = 0,
                inactive: UInt64 = 0) {
        self.used = used
        self.total = total
        self.pressure = pressure
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.compressed = compressed
        self.active = active
        self.wired = wired
        self.inactive = inactive
    }
}

// MARK: - 磁盘

/// 磁盘采样结果
///
/// 容量取根卷；读写速率、IOPS 与繁忙度为所有块存储驱动的增量之和，
/// 首帧（无基线）一律为 nil 而不是 0。
public struct DiskSnapshot: Sendable, Equatable {
    /// 已用容量（字节）= 总量 - 可用量
    public let used: UInt64
    /// 总量（字节）
    public let total: UInt64
    /// 读取速率（字节/秒）；无基线或统计不可读为 nil
    public let readBytesPerSecond: Double?
    /// 写入速率（字节/秒）；无基线或统计不可读为 nil
    public let writeBytesPerSecond: Double?
    /// 读 IOPS（次/秒）；无基线或计数器倒退为 nil
    public let readIOPS: Double?
    /// 写 IOPS（次/秒）；无基线或计数器倒退为 nil
    public let writeIOPS: Double?
    /// 繁忙度（0...1）= 读服务时间 + 写服务时间 / 采样间隔；无基线为 nil
    public let busyFraction: Double?

    public init(used: UInt64,
                total: UInt64,
                readBytesPerSecond: Double? = nil,
                writeBytesPerSecond: Double? = nil,
                readIOPS: Double? = nil,
                writeIOPS: Double? = nil,
                busyFraction: Double? = nil) {
        self.used = used
        self.total = total
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.readIOPS = readIOPS
        self.writeIOPS = writeIOPS
        self.busyFraction = busyFraction
    }
}

// MARK: - 温度 / 功耗 / 风扇

/// 温度、功耗与风扇采样结果
///
/// 三项均为可选：Apple Silicon 上 CPU 功耗与风扇转速当前不可得（实测结论见采样实现），
/// 温度为尽力而为的私有 API 读取，失败即 nil。
public struct ThermalSnapshot: Sendable, Equatable {
    /// CPU（SoC）温度（摄氏度）
    public let cpuTemperatureCelsius: Double?
    /// GPU 温度（摄氏度）
    public let gpuTemperatureCelsius: Double?
    /// GPU 功耗（瓦，估算值）
    ///
    /// 来源 IOReport Energy Model 的 "GPU Energy" 累加器（单位 nJ）差分除以采样间隔。
    /// **不是整机功耗**：同组的 CPU Energy / DRAM0 / ANE0 等通道在本机恒为 0，
    /// 无法合成整机功耗（实测见第二批指标调研 §2.1），UI 须标注「估算」。
    public let powerWatts: Double?
    /// 风扇转速（RPM）
    public let fanRPM: Int?

    public init(cpuTemperatureCelsius: Double? = nil,
                gpuTemperatureCelsius: Double? = nil,
                powerWatts: Double? = nil,
                fanRPM: Int? = nil) {
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.gpuTemperatureCelsius = gpuTemperatureCelsius
        self.powerWatts = powerWatts
        self.fanRPM = fanRPM
    }

    /// 是否没有任何可用值（全部 nil）
    public var isEmpty: Bool {
        cpuTemperatureCelsius == nil && gpuTemperatureCelsius == nil
            && powerWatts == nil && fanRPM == nil
    }
}
