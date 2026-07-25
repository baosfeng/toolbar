import Foundation

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
