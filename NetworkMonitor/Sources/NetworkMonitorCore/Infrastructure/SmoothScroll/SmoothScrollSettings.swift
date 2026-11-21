import Foundation

// MARK: - 平滑偏好键

/// 鼠标滚轮平滑的偏好键 —— 键名一经发布不可改名（会直接落到用户偏好里）
public enum SmoothScrollPreferenceKey {
    public static let enabled = "scroll.smoothing.enabled"
    public static let speedGain = "scroll.smoothing.speedGain"
    public static let duration = "scroll.smoothing.duration"
    public static let minStep = "scroll.smoothing.minStep"
    public static let reverse = "scroll.smoothing.reverse"

    /// 全部键（按设置页控件顺序；测试据此守住「五项都写了」）
    public static let all = [enabled, speedGain, duration, minStep, reverse]
}

// MARK: - 平滑偏好

/// 鼠标滚轮平滑偏好 —— 五项参数的唯一读写入口
///
/// 缺键一律回落默认（开关为关）：升级后不开就等于没有这个功能，不会因为新增键
/// 让老用户的滚动行为突然改变。越界值读取时就归一化（`clamped`），
/// 不让被手改坏的偏好进入引擎。
public struct SmoothScrollSettings {

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 当前参数（缺键回落默认；越界归一化）
    public var parameters: SmoothScrollParameters {
        SmoothScrollParameters(
            enabled: storage.bool(forKey: SmoothScrollPreferenceKey.enabled),
            speedGain: readPositive(SmoothScrollPreferenceKey.speedGain,
                                    fallback: SmoothScrollParameters.defaultSpeedGain),
            duration: readPositive(SmoothScrollPreferenceKey.duration,
                                   fallback: SmoothScrollParameters.defaultDuration),
            minStep: readPositive(SmoothScrollPreferenceKey.minStep,
                                  fallback: SmoothScrollParameters.defaultMinStep),
            reverseDirection: storage.bool(forKey: SmoothScrollPreferenceKey.reverse)
        ).clamped
    }

    /// 是否启用（开关的独立读取：启动时只需这一个布尔，不构造整套参数）
    public var isEnabled: Bool {
        storage.bool(forKey: SmoothScrollPreferenceKey.enabled)
    }

    /// 写入开关（只写用户显式操作的项）
    public func setEnabled(_ enabled: Bool) {
        storage.set(enabled, forKey: SmoothScrollPreferenceKey.enabled)
    }

    /// 写入速度增益（按区间归一化后落盘）
    public func setSpeedGain(_ value: Double) {
        write(value, key: SmoothScrollPreferenceKey.speedGain,
              range: SmoothScrollParameters.speedGainRange,
              fallback: SmoothScrollParameters.defaultSpeedGain)
    }

    /// 写入持续时间（秒）
    public func setDuration(_ value: Double) {
        write(value, key: SmoothScrollPreferenceKey.duration,
              range: SmoothScrollParameters.durationRange,
              fallback: SmoothScrollParameters.defaultDuration)
    }

    /// 写入最短步长（行）
    public func setMinStep(_ value: Double) {
        write(value, key: SmoothScrollPreferenceKey.minStep,
              range: SmoothScrollParameters.minStepRange,
              fallback: SmoothScrollParameters.defaultMinStep)
    }

    /// 写入反向滚动
    public func setReverseDirection(_ reverse: Bool) {
        storage.set(reverse, forKey: SmoothScrollPreferenceKey.reverse)
    }

    // MARK: 内部

    /// 读正数偏好：缺键（storage 对缺键返回 0）与非法值都回落默认
    ///
    /// 三项数值的区间下界都 > 0，所以「读到 0」即「没配过」；
    /// 手改出来的越界值交给 `clamped` 兜住。
    private func readPositive(_ key: String, fallback: Double) -> Double {
        let value = storage.double(forKey: key)
        return value > 0 ? value : fallback
    }

    private func write(_ value: Double,
                       key: String,
                       range: ClosedRange<Double>,
                       fallback: Double) {
        guard value.isFinite else {
            storage.set(fallback, forKey: key)
            return
        }
        storage.set(min(max(value, range.lowerBound), range.upperBound), forKey: key)
    }
}
