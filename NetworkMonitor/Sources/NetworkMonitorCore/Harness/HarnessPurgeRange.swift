import Foundation

// MARK: - 清理范围选项（设置页按天清理）

/// 清理范围的可选项 —— 设置页「清理历史数据」的范围选择器唯一数据源
///
/// 为什么不直接让 UI 拼 `HarnessRebuildScope`：范围要同时给出「展示名 + 天数的语义」，
/// 而 `.sinceDays(90)` 与「近 90 天」之间的映射一旦分散到视图里，文案与实际删的数据
/// 迟早对不上（`sinceDays(n)` 的口径是「含今天在内的最近 n 天」）。
/// 这里把两个口径绑死在一处，视图只遍历本枚举。
public enum HarnessPurgeRange: String, Sendable, Equatable, CaseIterable {
    /// 全部历史数据
    case all
    /// 近 90 天
    case days90
    /// 近 30 天
    case days30
    /// 近 7 天
    case days7

    /// 选择器上的短标签
    public var title: String {
        switch self {
        case .all: return "全部"
        case .days90: return "近 90 天"
        case .days30: return "近 30 天"
        case .days7: return "近 7 天"
        }
    }

    /// 对应的清理范围
    public var scope: HarnessRebuildScope {
        switch self {
        case .all: return .full
        case .days90: return .sinceDays(90)
        case .days30: return .sinceDays(30)
        case .days7: return .sinceDays(7)
        }
    }

    /// 二次确认里的完整说明（含口径：含今天在内的最近 n 天）
    public var confirmationText: String {
        switch self {
        case .all:
            return "全部历史数据"
        case .days90:
            return "近 90 天（含今天）的会话数据"
        case .days30:
            return "近 30 天（含今天）的会话数据"
        case .days7:
            return "近 7 天（含今天）的会话数据"
        }
    }

    /// 默认选项：全部（与旧版行为一致，不改变既有用户的肌肉记忆）
    public static let defaultRange = HarnessPurgeRange.all
}
