import Foundation

// MARK: - 剪贴板相对时间

/// 剪贴板相对时间格式化（纯函数，Core 层不依赖 AppKit，供 App 卡片与测试共用）
///
/// 口径（对应设计规格第 12 节测试项）：刚刚 / N 分钟前 / N 小时前 / N 天前 / M月d日。
/// 分档上界依次为 60 秒、1 小时、1 天、30 天，30 天及以上回退为「M月d日」。
/// 时钟漂移：`date` 晚于 `now`（时间差为负）时按「刚刚」处理，不展示负数文案。
public enum ClipboardRelativeTime {

    /// 生成中文相对时间文案
    /// - Parameters:
    ///   - date: 目标时间
    ///   - now: 参照时间（可注入，便于确定性验证）
    /// - Returns: 相对时间文案；时间差为负（目标时间在未来）返回「刚刚」
    public static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        // 分档边界由 RelativeTimeFormatting 统一给出，这里只负责拼中文文案
        switch RelativeTimeFormatting.bucket(seconds: seconds) {
        case .justNow:
            return "刚刚"
        case .minutes(let minutes):
            return "\(minutes) 分钟前"
        case .hours(let hours):
            return "\(hours) 小时前"
        case .days(let days):
            // 30 天及以上回退成日期：更久远的记录用「天前」既读不出年月也不比日期短
            guard seconds < 86_400 * 30 else { return dateText(date) }
            return "\(days) 天前"
        }
    }

    /// 超过 30 天回退的「M月d日」
    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
