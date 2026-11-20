import Foundation

// MARK: - 贴图默认透明度偏好键

/// 贴图默认透明度偏好键
///
/// 键名只在这里定义一次：设置页滑杆写入、贴图窗建窗读取、测试断言共用，
/// 避免「设置页写了一个键、贴图窗读的是另一个键」这类「设了不生效」的故障。
public enum PinDefaultAlphaPreferenceKey {
    /// 贴图默认透明度（0.3…1，缺键按满不透明）
    public static let pinDefaultAlpha = "snip.pinDefaultAlpha"
}

// MARK: - 默认透明度解析（纯逻辑）

/// 原始偏好值 → 合法透明度
///
/// 设置页滑杆与贴图窗都经这里取值，钳制规则只有一份。
public enum PinDefaultAlphaResolver {
    /// 下限：低于 30% 的贴图几乎看不清内容，用户也难以再找回该窗口
    public static let minimum: Double = 0.3
    /// 上限：满不透明
    public static let maximum: Double = 1
    /// 缺键 / 非法值时的默认：满不透明（与接线前一致，老用户外观不变）
    public static let defaultAlpha: Double = 1

    /// 缺键、非数值、NaN 一律回落默认；越界按区间钳制，滑杆之外的写入路径也能用。
    public static func resolve(raw: Double?) -> Double {
        guard let raw, raw.isFinite else { return defaultAlpha }
        return min(max(raw, minimum), maximum)
    }

    /// 从存储读当前默认透明度（读路径不写回，默认值将来变了没设置过的用户跟着变）
    public static func load(storage: any KeyValueStorage) -> Double {
        resolve(raw: storage.object(forKey: PinDefaultAlphaPreferenceKey.pinDefaultAlpha) as? Double)
    }
}
