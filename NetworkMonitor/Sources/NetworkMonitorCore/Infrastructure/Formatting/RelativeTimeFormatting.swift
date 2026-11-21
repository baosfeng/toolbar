import Foundation

// MARK: - 相对时间分档（全项目唯一实现）

/// 相对时间的唯一分档实现 —— 只出档位，不出文案
///
/// 三处调用方（剪贴板卡片、额度行状态、更新检查）文案各不相同（「刚刚」/「刚刚刷新」/
/// 「上次检查 3 分钟前」），但分档边界必须一致：边界一漂，同一时刻两个界面就会
/// 一个说「1 分钟前」一个说「刚刚」。所以这里只回答「落哪一档 + 档内计数」，文案由调用方拼。
public enum RelativeTimeFormatting {

    /// 相对时间档位
    public enum Bucket: Equatable, Sendable {
        /// 一分钟以内：含时钟回拨（未来时间戳）与非有限值
        case justNow
        /// N 分钟前（1…59）
        case minutes(Int)
        /// N 小时前（1…23）
        case hours(Int)
        /// N 天前（≥ 1）
        case days(Int)
    }

    /// 距今秒数 → 档位
    ///
    /// 边界左闭右开：59 秒仍是「刚刚」、60 秒进分钟档；3599 秒算 59 分钟、3600 秒进小时档；
    /// 86399 秒算 23 小时、86400 秒进天档。
    /// 负值与非有限值统一归「刚刚」：目标时间在未来是时钟回拨，显示「-3 分钟前」
    /// 比「刚刚」更容易被当成数据错误。
    public static func bucket(seconds: TimeInterval) -> Bucket {
        guard seconds.isFinite, seconds >= 0 else { return .justNow }
        if seconds < 60 { return .justNow }
        if seconds < 3_600 { return .minutes(Int(seconds / 60)) }
        if seconds < 86_400 { return .hours(Int(seconds / 3_600)) }
        return .days(Int(seconds / 86_400))
    }
}
