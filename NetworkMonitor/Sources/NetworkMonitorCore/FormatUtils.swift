import Foundation

// MARK: - 货币配置

/// 货币配置 — 数据库统一以 CNY（人民币）存储与展示
///
/// Reasonix sidecar 文件中的 cost 为 USD，写入数据库前需转换为 CNY。
public enum CurrencyConfig {
    /// 默认汇率（1 USD ≈ 7.2 CNY），历史数据迁移也按此汇率
    public static let defaultUsdToCnyRate: Double = 7.2
    /// UserDefaults 键，可用该键覆盖汇率
    public static let rateOverrideKey = "usdToCnyRate"

    /// 当前汇率（可通过 UserDefaults 键 `usdToCnyRate` 覆盖）
    public static var usdToCnyRate: Double {
        let saved = UserDefaults.standard.object(forKey: rateOverrideKey) as? Double
        return saved ?? defaultUsdToCnyRate
    }

    /// 将 USD 金额转换为 CNY
    public static func usdToCny(_ usd: Double) -> Double {
        usd * usdToCnyRate
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
