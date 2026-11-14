import Foundation

// MARK: - 菜单栏指标

/// 菜单栏可显示的指标 —— 展示名、默认启用与默认上屏顺序的唯一来源
///
/// 下沉到 Core 的原因：默认顺序与顺序整理判据要能被 TestRunner 直接断言
/// （可执行 target 无法被测试 target 引入），视图与偏好只读同一份定义。
public enum MenuBarMetric: String, CaseIterable, Sendable {
    // 网络
    case upSpeed, downSpeed, todayTraffic, weekTraffic
    // 系统
    case cpu, gpu, memory, memoryPressure, diskFree, diskIO, thermal, wifi, battery, load
    // Token
    case tokenToday, tokenCacheHit, tokenWeek

    /// 设置页行标题
    public var displayName: String {
        switch self {
        case .upSpeed: return "上传速度"
        case .downSpeed: return "下载速度"
        case .todayTraffic: return "今日流量"
        case .weekTraffic: return "本周流量"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .memoryPressure: return "内存压力"
        case .diskFree: return "磁盘空闲"
        case .diskIO: return "磁盘 I/O"
        case .thermal: return "温度/功耗"
        case .wifi: return "Wi-Fi"
        case .battery: return "电量"
        case .load: return "负载"
        case .tokenToday: return "Token 今日"
        case .tokenCacheHit: return "缓存命中率"
        case .tokenWeek: return "Token 7 天"
        }
    }

    /// 首次运行默认启用的指标（其余由用户自己打开）
    public var defaultEnabled: Bool {
        switch self {
        case .upSpeed, .downSpeed: return true
        default: return false
        }
    }

    /// 默认上屏顺序 —— **显式写死**，等于接入「自定义排序」之前的渲染顺序
    ///
    /// 与 `allCases` 的声明顺序不同（声明顺序是按领域分组，上屏顺序是先网速、再系统、再流量、最后 Token），
    /// 因此不能用 `allCases` 兜底：那样老用户升级后菜单栏外观会立刻变化。
    /// 新增指标请追加到语义相邻处，并同步 `MenuBarOrderTests` 的期望数组。
    public static let defaultOrder: [MenuBarMetric] = [
        .downSpeed, .upSpeed,
        .cpu, .gpu, .memory, .memoryPressure, .diskFree, .diskIO, .wifi, .battery, .thermal, .load,
        .todayTraffic, .weekTraffic,
        .tokenToday, .tokenCacheHit, .tokenWeek,
    ]

    /// 偏好里存的稳定 id（= rawValue；插入新 case 不会让旧排序错位）
    public static var stableIDs: [String] { allCases.map(\.rawValue) }

    /// 默认上屏顺序的 id 列表
    public static var defaultOrderIDs: [String] { defaultOrder.map(\.rawValue) }
}
