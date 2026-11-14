import Foundation

// MARK: - 额度 provider 公共解析工具

/// ISO8601 解析 —— 三家的时间字段格式不一（带 / 不带小数秒、`+00:00` 偏移），统一在这里兜底
public enum BillingISO8601 {

    /// 解析 ISO8601 字符串（先按带小数秒试，再按普通形态）
    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    /// epoch 秒 → 日期（服务端给 0 或负数时视为无效）
    public static func date(epochSeconds: Double?) -> Date? {
        guard let epochSeconds, epochSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: epochSeconds)
    }
}

// MARK: - 凭据清洗

/// 凭据清洗 —— 用户从浏览器 / 配置文件复制时容易带引号、首尾空白、`Bearer ` 或 `Cookie:` 前缀
public enum BillingCredentialNormalizer {

    /// 去掉首尾空白、成对引号与 `Bearer ` / `Cookie:` 前缀
    public static func token(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Bearer ", "bearer ", "Cookie:", "cookie:"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

// MARK: - 百分比换算

/// 额度百分比换算 —— 接口多数给「已用百分比」，App 内统一存「剩余比例」并钳制 0…1
public enum BillingPercentMath {

    /// 已用百分比（0…100，脏数据可能越界）→ 剩余比例（0…1）
    public static func remainingFraction(usedPercent: Double) -> Double {
        guard usedPercent.isFinite else { return 0 }
        return min(max(1 - usedPercent / 100, 0), 1)
    }

    /// 已用值 / 上限 → 剩余比例（上限非正时返回 0）
    public static func remainingFraction(used: Double, limit: Double) -> Double {
        guard limit > 0, used.isFinite else { return 0 }
        return min(max(1 - used / limit, 0), 1)
    }
}
