import Foundation
import NetworkMonitorCore

// MARK: - 条目类型中文名（纯逻辑）

/// 剪贴板条目类型的展示名 —— 菜单面板条目行与剪贴板面板详情区共用一份口径
///
/// 放 UI 目标是为了让 TestRunner 能直接断言（App 目标不可被测试 import）；
/// URL 文本按「链接」展示，其余按条目类型。
public enum ClipboardItemKindLabel {

    /// 类型中文名（URL 文本显示为「链接」）
    public static func label(for item: ClipboardItem) -> String {
        if item.kind == .text {
            let text = item.text ?? item.preview
            if text.hasPrefix("http://") || text.hasPrefix("https://") { return "链接" }
        }
        switch item.kind {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .rtf: return "富文本"
        }
    }
}
