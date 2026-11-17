import Foundation
import NetworkMonitorCore

// MARK: - 条目类型中文名（纯逻辑）

/// 剪贴板条目类型的展示名 —— 菜单面板条目行与剪贴板面板详情区共用一份口径
///
/// 放 UI 目标是为了让 TestRunner 能直接断言（App 目标不可被测试 import）；
/// URL 文本按「链接」展示，其余按条目类型。
public enum ClipboardItemKindLabel {

    /// 类型中文名（URL 文本显示为「链接」）
    ///
    /// 判定口径只有一处：`ClipboardTextClassifier`（Core 纯函数）。此前这里与卡片图标各写一份，
    /// 导致 www. 开头的链接在详情区显示「文本」、卡片却显示链接图标。
    public static func label(for item: ClipboardItem) -> String {
        if item.kind == .text, ClipboardTextClassifier.classify(item.text ?? item.preview).kind == .url {
            return "链接"
        }
        switch item.kind {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .rtf: return "富文本"
        }
    }

    /// 文本判定类型对应的 SF Symbol 名
    ///
    /// 只给三种类型特化符号；`.email` / `.color` / `.plain` 返回 nil，由卡片退回「等宽与否」的旧口径。
    /// 原因：类型标签（`label(for:)`）目前只对链接特化文案，若卡片给邮箱 / 颜色单独画图标，
    /// 同一条目又会在两处说不同的话 —— 那正是本次要消灭的分叉，故先只对齐已有特化。
    public static func symbolName(forTextKind kind: ClipboardTextKind) -> String? {
        switch kind {
        case .url: return "link"
        case .json: return "curlybraces"
        case .command: return "terminal"
        case .email, .color, .plain: return nil
        }
    }
}
