import Foundation

// MARK: - 系统监控偏好

/// 系统监控偏好 — 收敛全部 KeyValueStorage 键名与默认值
///
/// 禁止直读 UserDefaults.standard：一律通过注入的 KeyValueStorage 读写，
/// 测试用内存存储即可验证默认值与写入回读。
public final class SystemMonitorPreferences: Sendable {

    /// 面板可选显示项
    public enum PanelItem: String, CaseIterable, Sendable {
        case cpu
        case gpu
        case memory
        case disk
        case thermal
    }

    private enum Key {
        static let panelPrefix = "systemMonitor.panel."
        static let showsCPUInMenuBar = "systemMonitor.menuBar.showsCPU"
        static let sampleInterval = "systemMonitor.sampleInterval"
    }

    /// 采样周期允许区间（秒）— 过小会明显抬高采样开销，过大则失去实时性
    public static let minimumSampleInterval: TimeInterval = 0.5
    public static let maximumSampleInterval: TimeInterval = 5.0
    /// 默认采样周期（秒）
    public static let defaultSampleInterval: TimeInterval = 1.0
    /// 面板默认显示项：五项全部默认开启（温度走私有 API，取不到时按 nil 降级，不影响其余卡片）
    private static let defaultVisibleItems: Set<PanelItem> = [.cpu, .gpu, .memory, .disk, .thermal]

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    // MARK: 面板显示项

    /// 面板是否显示某项；未设置时按默认值（温度默认关闭）
    public func isPanelItemVisible(_ item: PanelItem) -> Bool {
        let key = Key.panelPrefix + item.rawValue
        guard storage.object(forKey: key) != nil else {
            return Self.defaultVisibleItems.contains(item)
        }
        return storage.bool(forKey: key)
    }

    /// 设置面板某项的显示开关
    public func setPanelItemVisible(_ visible: Bool, for item: PanelItem) {
        storage.set(visible, forKey: Key.panelPrefix + item.rawValue)
    }

    // MARK: 菜单栏

    /// 菜单栏是否显示 CPU 百分比；默认关闭（菜单栏空间有限）
    public var showsCPUInMenuBar: Bool {
        get {
            guard storage.object(forKey: Key.showsCPUInMenuBar) != nil else { return false }
            return storage.bool(forKey: Key.showsCPUInMenuBar)
        }
        set { storage.set(newValue, forKey: Key.showsCPUInMenuBar) }
    }

    // MARK: 采样周期

    /// 采样周期（秒），默认 1.0；读取时收敛到 [0.5, 5.0]，非法值回退默认
    public var sampleInterval: TimeInterval {
        get {
            guard storage.object(forKey: Key.sampleInterval) != nil else {
                return Self.defaultSampleInterval
            }
            return Self.clampedInterval(storage.double(forKey: Key.sampleInterval))
        }
        set { storage.set(Self.clampedInterval(newValue), forKey: Key.sampleInterval) }
    }

    /// 把任意输入收敛到允许区间；非有限值（NaN / 无穷）或非正值回退默认
    static func clampedInterval(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return defaultSampleInterval }
        return min(max(value, minimumSampleInterval), maximumSampleInterval)
    }
}
