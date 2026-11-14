import Foundation

// MARK: - 自绘行的读屏文案（纯口径）

/// 自绘行的读屏文案 —— 一行里的每一段都会念出来，空段不念
///
/// 抽出来的理由：两行式行有「行名 / 值 / 次列 / 副文本」四段，只拼行名会把占比与会话数丢掉；
/// 拼接规则放在纯层，TestRunner 才能钉住「哪些段必须念、空段怎么处理」。
public enum DrawnAccessibilityText {

    /// 一行的可读名：非空段按「行名 → 值 → 次列 → 副文本」用空格连接
    public static func row(title: String, value: String, secondary: String, detail: String) -> String {
        [title, value, secondary, detail]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
