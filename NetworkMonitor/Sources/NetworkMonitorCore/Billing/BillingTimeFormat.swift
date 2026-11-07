import Foundation

// MARK: - 时间显示格式（跟随系统 12/24 小时制）

/// 时间文案格式 — 全部额度相关时间显示的唯一入口
///
/// 原先三处（Hero、额度格、provider 块头）各自 `Locale(identifier: "en_US_POSIX")` +
/// 硬编码 `HH:mm`：系统设为 12 小时制时，其余 App 显示「6:00 PM」，
/// 只有本面板还在写「18:00」，同一块屏幕上两种时间写法。
///
/// 做法：**结构**用固定模板（保证 `重置` 之类的后缀位置稳定），**时分**交给
/// `dateFormat(fromTemplate:)` 由系统偏好决定（`h:mm a` / `HH:mm`），
/// 本地化是「跟随用户」而不是「跟随开发者」。
public enum BillingTimeFormat {
    /// 当前系统偏好下的时分模式（12 小时制含 AM/PM，24 小时制不含）
    public static var timePattern: String {
        DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: .current) ?? "HH:mm"
    }

    /// 组合出最终模板：当天 `时分`，跨天 `月/日 时分`
    public static func pattern(includeDate: Bool, suffix: String) -> String {
        (includeDate ? "M/d " : "") + timePattern + suffix
    }

    /// 格式化（默认本地时区）
    public static func string(_ date: Date,
                              includeDate: Bool = false,
                              suffix: String = "",
                              timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern(includeDate: includeDate, suffix: suffix)
        return formatter.string(from: date)
    }

    /// 当天只给时分，跨天补日期（`重置` 类文案共用）
    public static func reset(_ date: Date, suffix: String = " 重置") -> String {
        string(date, includeDate: !Calendar.current.isDateInToday(date), suffix: suffix)
    }
}
