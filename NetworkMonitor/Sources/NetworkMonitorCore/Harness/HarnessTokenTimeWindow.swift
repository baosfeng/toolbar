import Foundation

// MARK: - 时间口径（Asia/Shanghai）

/// Token 统计的时间口径
///
/// - 自然日与自然周边界一律按 Asia/Shanghai（UTC+8）
/// - 本周从周一 00:00 起算（firstWeekday = 2）
/// - 全部为纯函数，便于测试与跨线程调用
public enum HarnessTokenTimeWindow {
    /// 时区标识
    public static let timeZoneIdentifier = "Asia/Shanghai"

    /// 上海时区相对 UTC 的偏移秒数（当前恒为 +8h；从时区对象取值，避免硬编码）
    public static let utcOffsetSeconds: Int = {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 8 * 3600)!
        return zone.secondsFromGMT(for: Date(timeIntervalSince1970: 0))
    }()

    /// 一天的毫秒数
    public static let millisecondsPerDay: Int64 = 86_400_000

    /// 配置好的日历（公历 + 上海时区 + 周一为一周起始）
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    // MARK: - 日期键

    /// 毫秒时间戳对应的日期键（yyyy-MM-dd）
    public static func dayKey(tsMs: Int64) -> String {
        dayKey(for: Date(timeIntervalSince1970: Double(tsMs) / 1000))
    }

    /// 日期对应的日期键（yyyy-MM-dd，上海时区）
    public static func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    /// 由「上海天序号」还原日期键（供 SQL 按天分组的整数结果使用）
    ///
    /// 天序号定义：floor((unix 秒 + 偏移) / 86400)，与 dayIndex(forTsMs:) 一致
    public static func dayKey(dayIndex: Int64) -> String {
        let seconds = Double(dayIndex) * 86_400 - Double(utcOffsetSeconds)
        return dayKey(for: Date(timeIntervalSince1970: seconds))
    }

    /// 毫秒时间戳对应的上海天序号
    public static func dayIndex(forTsMs tsMs: Int64) -> Int64 {
        (tsMs / 1000 + Int64(utcOffsetSeconds)) / 86_400
    }

    /// 毫秒时间戳对应的上海自然小时（0-23）
    public static func hourIndex(forTsMs tsMs: Int64) -> Int {
        Int(((tsMs / 1000 + Int64(utcOffsetSeconds)) / 3_600) % 24)
    }

    // MARK: - 边界

    /// 今日 00:00 的毫秒时间戳
    public static func startOfDayMs(now: Date) -> Int64 {
        Int64((calendar.startOfDay(for: now).timeIntervalSince1970 * 1000).rounded())
    }

    /// 本周一 00:00 的毫秒时间戳
    public static func startOfWeekMs(now: Date) -> Int64 {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return Int64((start.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - 归属判定

    /// 是否属于 now 所在自然日
    public static func isToday(tsMs: Int64, now: Date) -> Bool {
        let start = startOfDayMs(now: now)
        return tsMs >= start && tsMs < start + millisecondsPerDay
    }

    /// 是否属于 now 所在自然周（周一 00:00 起）
    public static func isInThisWeek(tsMs: Int64, now: Date) -> Bool {
        tsMs >= startOfWeekMs(now: now)
    }
}
