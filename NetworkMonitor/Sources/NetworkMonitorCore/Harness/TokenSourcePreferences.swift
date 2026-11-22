import Foundation

// MARK: - 多来源偏好键

/// 多来源 token 监控的偏好键 —— **唯一出口**，禁止在别处散字符串
///
/// 键一旦进 UserDefaults 就不可再改名（老用户的配置会读不到），新增只能追加。
/// 命名空间统一 token.*；但 **dsh 源的根目录仍回落旧键 harness.sessionsRootPath**
/// （DSH 时期的命名，改名的代价是把老用户配的自定义目录弄丢），所以：
/// token.source.dsh.rootPath 缺省时读旧键 —— 零迁移。
///
/// 全部方法都是静态 + 显式传入 storage：设置页、面板、调度器、测试各用各的存储，
/// 不存在隐藏的 UserDefaults.standard 全局依赖。
public enum TokenSourcePreferences {

    // MARK: - 键名（新增键只能追加）

    /// Token 页当前选中来源（缺省 = 全部，即 nil）
    public static let selectedSourceKey = "token.selectedSource"
    /// 后台自动监控总开关（缺键 = 关）
    public static let autoIndexEnabledKey = "token.autoIndex.enabled"
    /// 后台自动监控间隔秒数（缺键 = 300）
    public static let autoIndexIntervalKey = "token.autoIndex.interval"
    /// 每来源偏好键的公共前缀：完整键 = 前缀 + 来源 rawValue + 后缀
    public static let perSourceKeyPrefix = "token.source."
    /// 启用开关键后缀（完整键 token.source.<id>.enabled）
    public static let enabledKeySuffix = ".enabled"
    /// 自定义根目录键后缀（完整键 token.source.<id>.rootPath）
    public static let rootPathKeySuffix = ".rootPath"

    // MARK: - 默认值

    /// 自动监控默认间隔（秒）
    public static let defaultAutoIndexInterval: TimeInterval = 300
    /// 自动监控间隔下限（秒）：一轮空跑只是一次目录枚举 + 一次 SQLite 查询，再密没有收益
    public static let minimumAutoIndexInterval: TimeInterval = 60

    // MARK: - 键构造（供诊断 / 测试 / 迁移使用）

    /// 某来源的启用开关键
    public static func enabledKey(for id: TokenSourceID) -> String {
        perSourceKeyPrefix + id.rawValue + enabledKeySuffix
    }

    /// 某来源的自定义根目录键
    public static func rootPathKey(for id: TokenSourceID) -> String {
        perSourceKeyPrefix + id.rawValue + rootPathKeySuffix
    }

    // MARK: - 启用开关

    /// 该来源是否参与索引
    ///
    /// 缺键时的默认值区分来源：**dsh 缺键即开**（它是既有链路，升级后行为必须零变化），
    /// **其余来源缺键即关**（项目惯例「后台能力默认关」；也避免未经用户同意就去扫别的
    /// 应用目录）。键一旦写过就以用户的选择为准，默认值翻转不会覆盖显式配置。
    public static func isEnabled(_ id: TokenSourceID, storage: any KeyValueStorage) -> Bool {
        let key = enabledKey(for: id)
        guard storage.object(forKey: key) != nil else { return id == TokenSourceID.legacy }
        return storage.bool(forKey: key)
    }

    /// 写入启用开关
    public static func setEnabled(_ enabled: Bool, for id: TokenSourceID, storage: any KeyValueStorage) {
        storage.set(enabled, forKey: enabledKey(for: id))
    }

    /// 已启用的来源（按 TokenSourceID.allCases 顺序，供索引与设置页使用）
    public static func enabledSources(_ storage: any KeyValueStorage) -> [TokenSourceID] {
        TokenSourceID.allCases.filter { isEnabled($0, storage: storage) }
    }

    // MARK: - 根目录

    /// 该来源的自定义根目录（未自定义或值为空白时为 nil）
    ///
    /// dsh 源在新键缺省时回落旧键 harness.sessionsRootPath（DSH 时期唯一可配的目录）。
    public static func rootPath(_ id: TokenSourceID, storage: any KeyValueStorage) -> String? {
        if let path = trimmed(storage.string(forKey: rootPathKey(for: id))) { return path }
        guard id == TokenSourceID.legacy else { return nil }
        return trimmed(storage.string(forKey: HarnessSourceDirectory.key))
    }

    /// 写入自定义根目录；传 nil 表示恢复默认（重新走环境变量与默认路径）
    ///
    /// 只删自己的键不动旧键：dsh 源的旧键由设置页的「恢复默认」一起清，
    /// 这里擅自删掉会让老用户的目录配置在只切了个新来源时凭空消失。
    public static func setRootPath(_ path: String?, for id: TokenSourceID, storage: any KeyValueStorage) {
        let key = rootPathKey(for: id)
        guard let path = trimmed(path) else {
            storage.removeObject(forKey: key)
            return
        }
        storage.set(path, forKey: key)
    }

    // MARK: - 选中来源

    /// Token 页当前来源（nil = 全部）
    ///
    /// 存的是 rawValue 字符串：rawValue 是发布后不可改的落库标识，读不认识的键按「全部」处理。
    public static func selectedSource(_ storage: any KeyValueStorage) -> TokenSourceID? {
        guard let raw = trimmed(storage.string(forKey: selectedSourceKey)) else { return nil }
        return TokenSourceID(rawValue: raw)
    }

    /// 写入当前来源（nil = 全部：删键而不是存 "all"，缺省即全部）
    public static func setSelectedSource(_ id: TokenSourceID?, storage: any KeyValueStorage) {
        guard let id else {
            storage.removeObject(forKey: selectedSourceKey)
            return
        }
        storage.set(id.rawValue, forKey: selectedSourceKey)
    }

    // MARK: - 自动监控

    /// 后台自动监控是否开启（缺键 = 关，遵循「后台能力默认关」）
    public static func autoIndexEnabled(_ storage: any KeyValueStorage) -> Bool {
        guard storage.object(forKey: autoIndexEnabledKey) != nil else { return false }
        return storage.bool(forKey: autoIndexEnabledKey)
    }

    /// 写入自动监控开关
    public static func setAutoIndexEnabled(_ enabled: Bool, storage: any KeyValueStorage) {
        storage.set(enabled, forKey: autoIndexEnabledKey)
    }

    /// 自动监控间隔（秒）：缺键 300，读出值同样按 [下限, ∞) 归一
    ///
    /// 读侧也做归一（不是只在写入时）：历史配置 / 手工改过的 plist 可能存了 5 秒，
    /// 不拦就会变成 5 秒一次的目录枚举。
    public static func autoIndexInterval(_ storage: any KeyValueStorage) -> TimeInterval {
        guard storage.object(forKey: autoIndexIntervalKey) != nil else { return defaultAutoIndexInterval }
        return normalizedInterval(storage.double(forKey: autoIndexIntervalKey))
    }

    /// 写入自动监控间隔（秒）；非有限值与 ≤0 按默认值落库
    public static func setAutoIndexInterval(_ seconds: TimeInterval, storage: any KeyValueStorage) {
        storage.set(normalizedInterval(seconds), forKey: autoIndexIntervalKey)
    }

    /// 间隔归一：≤0 / 非有限 → 默认值；其余夹到下限
    public static func normalizedInterval(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return defaultAutoIndexInterval }
        return max(minimumAutoIndexInterval, seconds)
    }

    // MARK: - 内部

    /// 去空白；空白字符串视同未设置
    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
