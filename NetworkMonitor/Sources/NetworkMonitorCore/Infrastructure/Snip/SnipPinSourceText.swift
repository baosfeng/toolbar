import Foundation

// MARK: - 贴图来源文本

/// 贴图窗口里「⌘⇧C 复制纯文本」要用到的来源文本判定（纯函数，可单测）
///
/// 官方贴图键位表：⌘⇧C 复制纯文本（如果该贴图是由文本转换而来）。
/// 只有文本 / HTML / 文件路径三类内容有可复制的原文本；图片与色卡没有，
/// 贴图窗据此给出「无内容可复制」的反馈，而不是静默吞掉按键。
public enum SnipPinSourceText {

    /// 纯文本来源本体（HTML 取原始 HTML，文件取路径列表拼接）
    public static func plainText(of content: SnipClipboardContent) -> String? {
        switch content {
        case .text(let value):
            return trimmedNonEmpty(value)
        case .html(let value):
            return trimmedNonEmpty(value)
        case .files(let paths):
            return SnipFilePathText.joined(paths)
        case .image, .color:
            return nil
        }
    }

    private static func trimmedNonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }
}
