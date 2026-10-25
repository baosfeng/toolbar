import Foundation

// MARK: - 额度格排版规则（纯逻辑）

/// 额度格排版规则 — 决定 1–3 列额度格在窄格里怎么摆
///
/// 抽成 Core 纯函数的原因：TestRunner 无法 import 可执行 target，排版判定若留在 UI 里就没有断言覆盖；
/// 而「几列算窄格」「角标与重置时间怎么衔接」本身与 AppKit 无关。
/// 实测（320pt 面板）：三列时每列可用 86pt，`已限流 · 10/26 08:00 重置` 宽约 107pt 放不下，
/// 所以三列必须让角标独占一行；一至两列（134pt / 278pt）可以同行。
public enum BillingLimitLayout {

    /// 额度格最多列数（5 小时 / 每周 / 每月）
    public static let maxColumns = 3

    /// 是否窄格（角标与重置时间需要分行）
    ///
    /// - Parameter columnCount: 实际使用的列数
    public static func isCompact(columnCount: Int) -> Bool {
        columnCount >= maxColumns
    }

    /// 同行时角标与重置时间之间的衔接文案（`已限流` → `已限流 ·`）
    public static func inlineBadge(_ badge: String) -> String {
        "\(badge) ·"
    }
}
