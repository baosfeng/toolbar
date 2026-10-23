import Foundation

// MARK: - 计费文案格式化

/// 美元金额格式化（如 "$72.50" / "$0.017"）
///
/// 小额按 3 位小数展示（Ollama 单次调用常见 0.00x 美元），大额保留 2 位。
/// 不用 `.currency` 样式：`en_US_POSIX` 下会输出 "$ 72.50"（带空格），
/// 面板等宽数字排版会因此抖动。
public func formatUSD(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US")
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    let digits = abs(value) >= 1 ? 2 : 3
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    return "$" + number
}

/// 非货币额度数量格式化（如 credits：76412 → "76,412"、157.4 → "157"）
///
/// 编码计划按 credits 计量而非美元，整数部分千分位分组，小数按需保留 1 位。
public func formatCreditAmount(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US")
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
}

/// 额度绝对值明细（如 "已用 76,412 / 150,000"；缺任一端时返回 nil）
public func formatLimitUsage(used: Double?, limit: Double?, unit: String?) -> String? {
    guard let used, let limit else { return nil }
    let text = "已用 \(formatCreditAmount(used)) / \(formatCreditAmount(limit))"
    guard let unit, !unit.isEmpty else { return text }
    return text + " " + unit
}

/// token 数量缩写（如 "10.6万" / "1360" / "1.2亿"）
///
/// 与菜单面板既有风格一致：≥1 万用「万」，≥1 亿用「亿」，保留 1 位小数。
public func formatTokenCount(_ value: Int) -> String {
    let absValue = abs(value)
    switch absValue {
    case 100_000_000...:
        return String(format: "%.1f亿", Double(absValue) / 100_000_000)
    case 10_000...:
        return String(format: "%.1f万", Double(absValue) / 10_000)
    default:
        return String(absValue)
    }
}

/// 剩余比例格式化（0...1 → "72%"）
public func formatPercent(_ fraction: Double) -> String {
    let clamped = min(max(fraction, 0), 1)
    return "\(Int((clamped * 100).rounded()))%"
}

/// 分桶时间标签
///
/// - 小时粒度："HH:00"（本地时区）
/// - 天粒度："M/d"（本地时区）
public func formatBucketLabel(_ date: Date, granularity: BillingGranularity) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    switch granularity {
    case .hour:
        formatter.dateFormat = "HH:00"
    case .day:
        formatter.dateFormat = "M/d"
    }
    return formatter.string(from: date)
}

/// 日期时间短文案（如 "9/15 09:30"，本地时区）
public func formatShortDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: date)
}
