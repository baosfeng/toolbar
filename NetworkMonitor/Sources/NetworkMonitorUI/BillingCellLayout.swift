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
        /// 数值不可得（字段缺失 / 分母非法）：不画填充、不参与告警分档
        case unavailable
    }

    /// 剩余比例 → 告警级别（<20% 红、<50% 橙、nil 不可得）
    ///
    /// nil 与 0 必须分开：0% 是「已用尽」（危险档），nil 是「取不到」（不画条、不告警）。
    public static func level(for fraction: Double?) -> Level {
        guard let fraction else { return .unavailable }
        if fraction < 0.2 { return .danger }
        if fraction < 0.5 { return .warn }
        return .normal
    }
}
