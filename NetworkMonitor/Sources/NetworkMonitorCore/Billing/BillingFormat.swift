import Foundation

// MARK: - 计费文案格式化

/// 原值数字格式化（不四舍五入、不补零）
///
/// 「服务端返回什么就显示什么」：不按固定小数位取整、不补尾零
/// （3.9 → "3.9"、0.22861 → "0.22861"、72.5 → "72.5"），整数部分按千分位分组
/// （76412 → "76,412"）。最多保留 6 位小数，仅用于消掉浮点运算噪声
/// （如 3.74 / 100 * 100 → 3.7399999…，比值换算后显示仍应是 3.74）。
public func formatExactNumber(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US")
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maxExactFractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

/// 原值小数位上限 — 只用于消除浮点噪声，不改变服务端返回值本身的有效位数
private let maxExactFractionDigits = 6

/// 美元金额格式化（如 "$72.5" / "$0.22861"）
///
/// 直接展示服务端返回的原值，不做四舍五入、不补零。
/// 不用 `.currency` 样式：`en_US_POSIX` 下会输出 "$ 72.5"（带空格），
/// 面板等宽数字排版会因此抖动。
public func formatUSD(_ value: Double) -> String {
    "$" + formatExactNumber(value)
}

/// 非货币额度数量格式化（如 credits：76412 → "76,412"、3.9 → "3.9"）
///
/// 编码计划按 credits 计量而非美元，同样原值展示、不做四舍五入。
public func formatCreditAmount(_ value: Double) -> String {
    formatExactNumber(value)
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

/// 剩余比例格式化（0...1 → "72.5%"）
///
/// 百分比按服务端返回值原样展示：3.74% 就是 "3.74%"，不取整成 "4%"。
/// 只做 0...1 钳制（超界数据按满额 / 空额处理）。
public func formatPercent(_ fraction: Double) -> String {
    let clamped = min(max(fraction, 0), 1)
    return formatExactNumber(clamped * 100) + "%"
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
/// 余额快照摘要（调试日志用，如「5 小时 98% · 每周 99% · 每月 48%」）
///
/// 生产日志里没有额度数值就无从判断「额度页没数据」是没配凭据、接口失败还是解析偏移；
/// 这里给一条可搜索的摘要，百分比按原值展示，与额度页口径一致。
public func formatBalanceSummary(_ balance: BillingBalance) -> String {
    if !balance.percentLimits.isEmpty {
        return balance.percentLimits.map { limit -> String in
            let badge = limit.badge.map { " \($0)" } ?? ""
            return "\(limit.title) \(formatPercent(limit.remainingFraction))\(badge)"
        }.joined(separator: " · ")
    }
    if let total = balance.totalAvailableUSD {
        return "可用 \(formatUSD(total))"
    }
    return "无额度数据"
}
