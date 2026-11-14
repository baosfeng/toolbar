import Foundation

// MARK: - 额度格的纯布局口径

/// 额度格的口径判定 —— 与视图无关，TestRunner 可直接断言
///
/// 之所以抽到 UI 库：这三条判定原来散在视图里（`level(...)` / `syncResetRow` / 角标拼接），
/// 视图改成自绘后仍要保留同一套口径，抽出来才能测、才能被其它展示层复用。
public enum BillingCellLayout {

    /// 告警级别（决定进度条填充色）
    public enum Level: Equatable {
        case normal
        case warn
        case danger
    }

    /// 剩余比例 → 告警级别（<20% 红、<50% 橙）
    public static func level(for fraction: Double) -> Level {
        if fraction < 0.2 { return .danger }
        if fraction < 0.5 { return .warn }
        return .normal
    }

    /// 角标文案：同行时带分隔符（“已限流 ·”），窄格或没有重置时间时原样
    public static func badgeText(_ badge: String?, hasReset: Bool, compact: Bool) -> String? {
        guard let badge else { return nil }
        return (compact || !hasReset) ? badge : badge + " ·"
    }

    /// 角标行的行数（0 = 整行不画）
    public static func footerLineCount(hasBadge: Bool, hasReset: Bool, compact: Bool) -> Int {
        if compact {
            return (hasBadge ? 1 : 0) + (hasReset ? 1 : 0)
        }
        return (hasBadge || hasReset) ? 1 : 0
    }
}