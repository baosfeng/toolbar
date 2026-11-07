import Foundation
import NetworkMonitorCore

// MARK: - 时间格式跟随系统偏好

/// 额度页时间文案：结构固定、时分跟随系统 12/24 小时制
func runBillingTimeFormatTests() {
    print("🧪 Testing 额度时间格式...")

    // 模板按系统偏好派生：12 小时制含 a（AM/PM），24 小时制不含
    let template = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: .current) ?? "HH:mm"
    let systemUses12Hour = template.contains("a")
    assertEqual(BillingTimeFormat.timePattern.contains("a"), systemUses12Hour,
                "时分模板与系统偏好一致（12/24 小时制）")

    // 用固定时区构造时刻，验证「结构」不受格式化入口改动影响
    var calendar = Calendar(identifier: .gregorian)
    let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    calendar.timeZone = timeZone
    let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12, minute: 5))!

    let noonText = BillingTimeFormat.string(noon, timeZone: timeZone)
    assertEqual(noonText.contains("12:05"), true, "正午 12:05 出现在文案里")
    assertEqual(noonText.contains("无重置窗口"), false, "正常时刻不会出现降级文案")

    // 12 小时制下「12:05」后面要带 AM/PM，24 小时制不带
    if systemUses12Hour {
        assertEqual(noonText.contains("PM"), true, "系统 12 小时制时带 PM")
    } else {
        assertEqual(noonText.contains("AM") || noonText.contains("PM"), false, "系统 24 小时制时不带 AM/PM")
    }

    // 跨天补日期、当天不补（用同一入口保证两处口径一致）
    let today = Date()
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let todayText = BillingTimeFormat.reset(today)
    let tomorrowText = BillingTimeFormat.reset(tomorrow)
    assertEqual(todayText.hasSuffix("重置"), true, "当天文案以「重置」结尾")
    assertEqual(tomorrowText.hasSuffix("重置"), true, "跨天文案同样以「重置」结尾")
    assertEqual(tomorrowText.count > todayText.count, true, "跨天文案多出日期部分")
    assertEqual(todayText.contains("/"), false, "当天文案不含月/日")

    print("✅ 额度时间格式 works")
}
