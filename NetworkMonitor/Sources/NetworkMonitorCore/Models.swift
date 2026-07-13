import Foundation

// MARK: - 事件类型

/// 系统事件类型
public enum EventType: String, Sendable {
    // 应用事件
    case appOpen = "app_open"
    case appClose = "app_close"
    case appSwitch = "app_switch"
    case windowTitle = "window_title"

    // 屏幕事件
    case screenSleep = "screen_sleep"
    case screenWake = "screen_wake"

    // 系统事件
    case systemSleep = "system_sleep"
    case systemWake = "system_wake"

    // 电源事件（暂未实现，预留）
    case powerAC = "power_ac"
    case powerBattery = "power_battery"

    // 输入事件
    case keyPress = "key_press"

    // 系统采样
    case systemSample = "system_sample"
}

// MARK: - 今日统计

/// 今日统计数据结构
public struct TodayStats: Sendable {
    /// 活跃时间（秒）
    public let activeSeconds: TimeInterval
    /// 击键总数
    public let keyPressCount: Int
    /// 亮屏时间（秒）
    public let screenOnSeconds: TimeInterval
    /// 息屏时间（秒）
    public let screenOffSeconds: TimeInterval
    /// 应用排行
    public let appRanking: [AppUsage]
    /// 最近的 CPU 使用率
    public let cpuUsage: Double
    /// 内存使用（MB）
    public let memoryUsedMB: Int
    /// 总内存（MB）
    public let memoryTotalMB: Int
    /// 网络下载速率（字节/秒）
    public let netDownloadSpeed: UInt64
    /// 网络上传速率（字节/秒）
    public let netUploadSpeed: UInt64

    public static let empty = TodayStats(
        activeSeconds: 0, keyPressCount: 0,
        screenOnSeconds: 0, screenOffSeconds: 0,
        appRanking: [], cpuUsage: 0,
        memoryUsedMB: 0, memoryTotalMB: 0,
        netDownloadSpeed: 0, netUploadSpeed: 0
    )

    public init(
        activeSeconds: TimeInterval, keyPressCount: Int,
        screenOnSeconds: TimeInterval, screenOffSeconds: TimeInterval,
        appRanking: [AppUsage], cpuUsage: Double,
        memoryUsedMB: Int, memoryTotalMB: Int,
        netDownloadSpeed: UInt64, netUploadSpeed: UInt64
    ) {
        self.activeSeconds = activeSeconds
        self.keyPressCount = keyPressCount
        self.screenOnSeconds = screenOnSeconds
        self.screenOffSeconds = screenOffSeconds
        self.appRanking = appRanking
        self.cpuUsage = cpuUsage
        self.memoryUsedMB = memoryUsedMB
        self.memoryTotalMB = memoryTotalMB
        self.netDownloadSpeed = netDownloadSpeed
        self.netUploadSpeed = netUploadSpeed
    }
}

// MARK: - 应用使用数据

/// 应用使用数据
public struct AppUsage: Comparable, Sendable {
    public let name: String
    public let bundleID: String
    public let duration: TimeInterval // 前台使用秒数

    public init(name: String, bundleID: String, duration: TimeInterval) {
        self.name = name
        self.bundleID = bundleID
        self.duration = duration
    }

    public static func < (lhs: AppUsage, rhs: AppUsage) -> Bool {
        lhs.duration < rhs.duration
    }
}
