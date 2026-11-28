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

    // MARK: - 标签（菜单栏前缀）

    /// 完整标签 —— **逐字等于接入「菜单栏标签」偏好之前的硬编码前缀**
    ///
    /// 自带尾随空格：`↓` / `↑` 两项速度的前缀与数值之间没有空格（`↓1.2M`），
    /// 其余都有（`CPU 40%`）；把这条差异写进标签本身，渲染处不用再判要不要补空格。
    /// 任何一项改动都会直接改变所有老用户的菜单栏外观，改前先看 `MenuBarLabelTests` 的逐字断言。
    public var fullLabel: String {
        switch self {
        case .upSpeed: return "↑"
        case .downSpeed: return "↓"
        case .todayTraffic: return "Today "
        case .weekTraffic: return "Wk "
        case .cpu: return "CPU "
        case .gpu: return "GPU "
        case .memory: return "MEM "
        case .memoryPressure: return "P "
        case .diskFree: return "Disk "
        case .diskIO: return "R "
        case .thermal: return "Temp "
        case .wifi: return "WiFi "
        case .battery: return "BAT "
        case .load: return "L "
        case .tokenToday: return "Token "
        case .tokenCacheHit: return "HIT "
        case .tokenWeek: return "7d "
        }
    }

    /// 第二片段的完整标签（只有磁盘 I/O 一次出两段：读 `R` + 写 `W`）
    public var secondaryFullLabel: String? {
        self == .diskIO ? "W " : nil
    }

    /// 短标签 —— 1–2 字符，用户口述的省宽诉求（`Token 2.5B` → `T 2.5B`）
    ///
    /// 17 项在一两个字符里不可能互不重复，下表是**刻意**的取舍：
    /// 高频项优先占到字母（C / G / M / P / D / B / L / H / T），温度用 `°`、
    /// 流量用「今 / 周」、Token 7 天用 `7` 把字母让给更常用的项。
    /// 撞车时用户可在设置页「逐项自定义」里改掉任意一项。
    public var shortLabel: String {
        switch self {
        case .upSpeed: return "↑"
        case .downSpeed: return "↓"
        case .todayTraffic: return "今 "
        case .weekTraffic: return "周 "
        case .cpu: return "C "
        case .gpu: return "G "
        case .memory: return "M "
        case .memoryPressure: return "P "
        case .diskFree: return "D "
        case .diskIO: return "R "
        case .thermal: return "° "
        case .wifi: return "W "
        case .battery: return "B "
        case .load: return "L "
        case .tokenToday: return "T "
        case .tokenCacheHit: return "H "
        case .tokenWeek: return "7 "
        }
    }

    /// 第二片段的短标签（只有磁盘 I/O 一次出两段：读 `R` + 写 `W`）
    public var secondaryShortLabel: String? {
        self == .diskIO ? "W " : nil
    }

    /// SF Symbol 名 —— 供设置页「逐项自定义」每行出图标（可选，取不到就不给图）
    ///
    /// 菜单栏本身不渲染这些符号：`NSStatusBarButton` 只有一枚 `image` + 一段标题，
    /// 17 项各出一枚图标、还要与 ⚠️ / ⏸ 前缀逐片段混排，只能自绘整条状态栏图 —— 属另一件事，
    /// 见设置页「菜单栏标签」行的副标题说明。
    ///
    /// 消费者：MenuBarStatusRenderer（设置页逐项勾选「图标」后，菜单栏整条内容自绘，
    /// 该项的前缀换成这枚符号、数值保留）。未勾选的项仍走纯文本路径。
    public var symbolName: String? {
        switch self {
        case .upSpeed: return "arrow.up"
        case .downSpeed: return "arrow.down"
        case .todayTraffic: return "calendar"
        case .weekTraffic: return "calendar.badge.clock"
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .memoryPressure: return "gauge"
        case .diskFree: return "internaldrive"
        case .diskIO: return "arrow.left.arrow.right"
        case .thermal: return "thermometer.medium"
        case .wifi: return "wifi"
        case .battery: return "battery.75"
        case .load: return "chart.line.uptrend.xyaxis"
        case .tokenToday: return "chart.bar.fill"
        case .tokenCacheHit: return "bolt.horizontal"
        case .tokenWeek: return "clock.arrow.circlepath"
        }
    }

    /// 该项输出的是「计数」还是「速率」
    ///
    /// 速率类（下载 / 上传 / 磁盘读写）保持 K / M / B + `/s`：`亿/秒` 在中文里不通顺，
    /// 面板与设置页也没有任何一处这么写；计数类（今日 / 本周流量、Token 三个数）必须跟随
    /// 设置页「数值单位」，否则用户把单位切到「万 / 亿」后菜单栏仍写 `2.5B`。
    public var isCounter: Bool {
        switch self {
        case .todayTraffic, .weekTraffic, .tokenToday, .tokenWeek: return true
        default: return false
        }
    }
}
