import Foundation

// MARK: - 货币配置

/// 货币配置 — 数据库历史金额字段统一以 CNY（人民币）存储与展示
///
/// 历史数据迁移（v1）需要 USD → CNY 换算，汇率通过 `KeyValueStorage` 读取
/// （不再直读 UserDefaults），测试可注入 `storageOverride` 隔离全局状态。
public final class CurrencyConfig: @unchecked Sendable {
    /// 全局共享实例
    public static let shared = CurrencyConfig()

    /// 默认汇率（1 USD ≈ 7.2 CNY），历史数据迁移也按此汇率
    public static let defaultUsdToCnyRate: Double = 7.2
    /// 键值存储键，可用该键覆盖汇率
    public static let rateOverrideKey = "usdToCnyRate"

    /// 可注入的键值存储（测试用）；nil 时使用 AppContext 共享存储
    public var storageOverride: KeyValueStorage?

    /// 当前汇率（可通过键值存储的 `usdToCnyRate` 键覆盖）
    public var usdToCnyRate: Double {
        let storage = storageOverride ?? AppContext.shared.storage
        let saved = storage.double(forKey: Self.rateOverrideKey)
        return saved > 0 ? saved : Self.defaultUsdToCnyRate
    }

    /// 将 USD 金额转换为 CNY
    public func usdToCny(_ usd: Double) -> Double {
        usd * usdToCnyRate
    }

    private init() {}
}

// MARK: - 时区配置

/// SQLite 时区偏移 — 统计 SQL 统一使用本地时区（而非硬编码 +8 小时）
///
/// SQLite 的 `date()` 函数接受 `'+N hours'` 形式的修饰符。
/// 表达式索引的表达式必须与查询完全一致才能命中，因此
/// 索引创建与查询语句共用本配置（App 启动时计算一次，时区变更需重启）。
public enum SqliteTimeZone {
    /// 当前时区相对 UTC 的偏移修饰符，如 "+8 hours"、"-5 hours"、"+5.5 hours"
    public static var offsetModifier: String {
        let seconds = TimeZone.current.secondsFromGMT()
        let hours = Double(seconds) / 3600.0
        let value = String(format: "%g", hours)
        return value.hasPrefix("-") ? "\(value) hours" : "+\(value) hours"
    }
}
