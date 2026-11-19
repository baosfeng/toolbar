import Foundation

// MARK: - 更新检查偏好

/// 更新检查偏好 — 只记「上次检查时间」，用来给自动检查限频（24 小时一次）
///
/// 写法参考 `NumberUnitPreferences`：键缺失即「从未检查」，读取不写默认值，
/// 测试注入内存存储不污染真实偏好。
///
/// 为什么需要这条键：启动后自动查一次，若不限频则每次启动都打一次 GitHub 接口——
/// 匿名接口每小时 60 次，用户一天重启十几次就会撞限流，界面随即显示「无法检查」。
public struct UpdateCheckPreferences {

    /// 上次检查时间（Unix 秒）
    public static let lastCheckAtKey = "update.lastCheckAt"

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 上次检查时间（键缺失 / 值非法 → nil）
    ///
    /// 判「存过没有」用 `object(forKey:)` 而不是 `double(forKey:)`：
    /// 后者键缺失时返回 0，会被当成 1970 年，自动检查判据永远「到点」。
    public var lastCheckAt: Date? {
        guard storage.object(forKey: Self.lastCheckAtKey) != nil else { return nil }
        let seconds = storage.double(forKey: Self.lastCheckAtKey)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 记录一次检查（每次检查完成都写，无论成功失败：失败同样计入限频，
    /// 否则断网时会每次启动都重试一次）
    public func markChecked(at date: Date = Date()) {
        storage.set(date.timeIntervalSince1970, forKey: Self.lastCheckAtKey)
    }

    // MARK: 自动安装

    /// 「发现新版本后自动下载安装」开关
    ///
    /// 默认**关闭**：替换应用包是破坏性动作（ad-hoc 签名下会让 TCC 授权失效），
    /// 缺键即关，只有用户明确打开过才生效。
    public static let autoInstallKey = "update.autoInstall"

    /// 是否已开启自动安装（缺键 = 关）
    public var autoInstallEnabled: Bool {
        guard storage.object(forKey: Self.autoInstallKey) != nil else { return false }
        return storage.bool(forKey: Self.autoInstallKey)
    }

    /// 写入自动安装开关（只记意图，真正的安装时机由服务判）
    public func setAutoInstallEnabled(_ enabled: Bool) {
        storage.set(enabled, forKey: Self.autoInstallKey)
    }
}