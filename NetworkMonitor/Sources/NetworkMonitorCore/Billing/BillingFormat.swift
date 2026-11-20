import Foundation

// MARK: - 计费文案格式化

/// 原值数字格式化（不四舍五入、不补零）
///
/// 「服务端返回什么就显示什么」：不按固定小数位取整、不补尾零
/// （3.9 → "3.9"、0.22861 → "0.22861"、72.5 → "72.5"），整数部分按千分位分组
/// （76412 → "76,412"）。最多保留 6 位小数，仅用于消掉浮点运算噪声
/// （如 3.74 / 100 * 100 → 3.7399999…，比值换算后显示仍应是 3.74）。
public func formatExactNumber(_ value: Double) -> String {
    GroupedNumberFormatting.exact(value, maxFractionDigits: maxExactFractionDigits)
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

/// 按币种格式化余额金额（USD → "$12.5"、CNY → "¥110.00"、其它 → "110.00 CHF"）
///
/// 额度 provider 各报各的币种（DeepSeek 国内账户报 CNY、OpenRouter 报 USD），
/// 统一入口在这里，UI 不再假定「余额都是美元」。
public func formatCurrencyAmount(_ value: Double, code: String) -> String {
    switch code.uppercased() {
    case "USD": return formatUSD(value)
    case "CNY", "RMB": return "¥" + formatExactNumber(value)
    default: return formatExactNumber(value) + " " + code.uppercased()
    }
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

/// token 数量缩写（automatic：`106K` / `1.2B`；chinese：`10.6万` / `1.2亿`）
///
/// **迁移事实（勿当回归 bug 修回去）**：改造前额度页这里恒用「万 / 亿」（与 Token 页的
/// K/M/B 各一套），本次按用户「两个页面数值口径要统一」的要求，改为跟随设置页的
/// 「数值单位」偏好；默认档 automatic 下额度页的 token 会从 `10.6万` 变成 `106K`，
/// 与 Token 页完全一致。切到中文档则整 App（含 Token 页）统一显示万 / 亿。
///
/// 口径收敛在 `NumberUnits.scale`；调用方（额度页视图）不需要改代码 —— 签名与返回形态不变。
public func formatTokenCount(_ value: Int) -> String {
    NumberUnits.scale(Double(value)).text
}

/// 剩余比例格式化（0...1 → "72.5%"）
///
/// 百分比按服务端返回值原样展示：3.74% 就是 "3.74%"，不取整成 "4%"。
/// 只做 0...1 钳制（超界数据按满额 / 空额处理）。
///
/// 用途：无障碍朗读、日志摘要、明细等「需要精确值」的位置。
/// 额度卡里的大号数字请用 `formatPercentCompact`（原值最多 6 位小数会把版式撑坏）。
public func formatPercent(_ fraction: Double) -> String {
    let clamped = min(max(fraction, 0), 1)
    return formatExactNumber(clamped * 100) + "%"
}

/// 不可得占位符 —— 额度数值取不到时的统一文案（不是 0%，也不是空串）
public let billingUnavailablePlaceholder = "—"

/// 可选百分比的展示口径：nil（不可得）→ 「—」，其余与 `formatPercent` 同源
///
/// 判据：只有「服务端明确给出 0」才显示 0%；字段缺失 / 分母非法一律「—」。
public func formatPercent(_ fraction: Double?) -> String {
    guard let fraction else { return billingUnavailablePlaceholder }
    return formatPercent(fraction)
}

/// 额度卡大号数字用的紧凑百分比（0...1 → "49.06%"）
///
/// 规则：
/// - 0...1 钳制（超界按满额 / 空额处理，与 `formatPercent` 一致）
/// - **最多 2 位小数并去尾零**：42.00 → "42%"、49.058667 → "49.06%"、99.686 → "99.69%"
/// - NaN / ±inf 降级为「—」（不显示 "nan%"）
///
/// 为什么单独一个函数：服务端会返回 1 - 157/50000 这种长小数，
/// 旧版 16pt 字号还能忍，卡内 19–24pt 时六位小数直接毁版式；
/// `formatPercent` 保持原值展示不动，避免改掉日志与无障碍的口径。
public func formatPercentCompact(_ fraction: Double?) -> String {
    guard let fraction else { return billingUnavailablePlaceholder }
    return formatPercentCompact(fraction)
}

/// 非可选紧凑百分比（内部复用；nil 口径见上面的重载）
func formatPercentCompact(_ fraction: Double) -> String {
    guard fraction.isFinite else { return billingUnavailablePlaceholder }
    let clamped = min(max(fraction, 0), 1)
    return GroupedNumberFormatting.trimmedDecimal(clamped * 100, decimals: 2) + "%"
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
// MARK: - 刷新日志口径（三态可分辨）

/// 三态日志的固定前缀 —— 现场用一条 grep 就能把「失败 / 成功但取不到 / 真的 0」分开
///
/// 这三条是额度页排障的唯一入口，文案由纯函数产出，改动前先改这里的测试。
public enum BillingLogLine {

    /// 失败日志的前缀（失败文案在 BillingMonitor 里生成，这里只登记可 grep 的锚点）
    public static let failurePrefix = "计费查询失败"

    /// 请求成功：窗口数 + 首个窗口剩余比例 + 不可得项数 + 数值摘要
    ///
    /// `summary` 形如「5 小时 98% · 每周 99%」，不含凭据与 URL（走 LogRedaction 之外的纯数值路径）。
    public static func success(providerID: String, balance: BillingBalance) -> String {
        let firstText = balance.percentLimits.first.map { limit in
            "\(limit.title)=\(formatPercent(limit.remainingFraction))"
        } ?? "无百分比窗口"
        let unavailableCount = balance.percentLimits.filter(\.isUnavailable).count
        return "计费刷新成功（\(providerID)）：窗口 \(balance.percentLimits.count) 条｜首个 \(firstText)｜"
            + "不可得 \(unavailableCount)｜\(formatBalanceSummary(balance))"
    }

    /// 请求成功但数值不可得（与「真的 0%」必须能分开）
    public static func unavailable(providerID: String, titles: [String]) -> String {
        "额度数据不完整（\(providerID)）：\(titles.joined(separator: " / ")) 剩余比例不可得"
            + "（上限缺失或非法），界面按「—」展示"
    }

    /// 请求成功但响应里一条额度都没有
    public static func empty(providerID: String) -> String {
        "计费刷新成功（\(providerID)）：响应里没有任何额度值"
    }

    /// 一次成功刷新的全部日志行（无余额时回落到「空响应」一条）
    public static func refreshLines(providerID: String, balance: BillingBalance?) -> [String] {
        guard let balance else { return [empty(providerID: providerID)] }
        var lines = [success(providerID: providerID, balance: balance)]
        let missing = balance.percentLimits.filter(\.isUnavailable).map(\.title)
        if !missing.isEmpty { lines.append(unavailable(providerID: providerID, titles: missing)) }
        return lines
    }
}
/// 余额快照摘要（调试日志用，如「5 小时 98% · 每周 99% · 每月 48%」）
///
/// 生产日志里没有额度数值就无从判断「额度页没数据」是没配凭据、接口失败还是解析偏移；
/// 这里给一条可搜索的摘要，百分比按原值展示，与额度页口径一致。
public func formatBalanceSummary(_ balance: BillingBalance) -> String {
    if !balance.percentLimits.isEmpty {
        return balance.percentLimits.map { limit -> String in
            let badge = limit.badge.map { " \($0)" } ?? ""
            // 不可得的窗口在日志里点名「不可得」，与「真的是 0%」区分开
            guard let fraction = limit.remainingFraction else {
                return "\(limit.title) \(billingUnavailablePlaceholder) 不可得\(badge)"
            }
            return "\(limit.title) \(formatPercent(fraction))\(badge)"
        }.joined(separator: " · ")
    }
    if let total = balance.totalAvailableUSD {
        return "可用 \(formatCurrencyAmount(total, code: balance.currencyCode))"
    }
    return "无额度数据"
}
