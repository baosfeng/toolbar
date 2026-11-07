import Foundation

// MARK: - 时间口径的界面说明

/// Token 页时间口径的说明文案（工具提示 / 读屏共用一处，Core 内以便测试断言）
///
/// 统计口径固定按 `Asia/Shanghai` 切自然日与自然周（见 `HarnessTokenTimeWindow`），
/// 不跟随系统时区。用户把 Mac 时区改到别的地区后，「今日」与系统日历不是同一天，
/// 而这个差异原本在界面上没有任何说明——只能当成「统计不准」。
/// 改口径会让历史窗口整体平移、数字突变，所以选择**把口径写出来**而不是改算法。
public enum TokenTimeZoneNote {
    public static let text = "自然日 / 自然周按 Asia/Shanghai（UTC+8）切分，不跟随系统时区"
}
