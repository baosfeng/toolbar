import Foundation

// MARK: - 货币配置

/// 货币配置 — 数据库统一以 CNY（人民币）存储与展示
///
/// Reasonix sidecar 文件中的 cost 为 USD，写入数据库前需转换为 CNY。
/// 汇率通过 `KeyValueStorage` 读取（不再直读 UserDefaults），
/// 测试可注入 `storageOverride` 隔离全局状态。
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

// MARK: - 格式化工具

/// 通用的格式化工具方法集
public enum FormatUtils {

    /// 短格式 Token 数（中文单位：万/亿）
    /// - Parameter count: Token 数量
    /// - Returns: 格式化后的字符串，如 "1.2万"、"3.5亿"
    nonisolated public static func tokenShort(_ count: Int) -> String {
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }

    /// 短格式花费（人民币 ¥）
    /// - Parameter cost: 金额（元）
    /// - Returns: 格式化后的字符串，如 "¥0.0040"、"¥0.050"、"¥1.23"
    nonisolated public static func costShort(_ cost: Double) -> String {
        if cost < 0.01 { return String(format: "¥%.4f", cost) }
        if cost < 1 { return String(format: "¥%.3f", cost) }
        return String(format: "¥%.2f", cost)
    }
}
