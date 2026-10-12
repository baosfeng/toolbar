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
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) 小时前" }
        if seconds < 86_400 * 30 { return "\(Int(seconds / 86_400)) 天前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
