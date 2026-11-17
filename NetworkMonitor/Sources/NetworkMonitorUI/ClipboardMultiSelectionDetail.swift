import Foundation

// MARK: - 多选态文案（纯逻辑）

/// 多选态的界面文案 —— 详情区摘要、删除确认、删除结果三处口径集中在这里
///
/// 视图与控制器只取字符串，不各自拼文案：条数文案一旦分散，各处就会出现
/// 「已选 3 条」与「删除 3 项」这种同一件事两种说法的漂移。
public enum ClipboardMultiSelectionDetail {

    /// 详情区摘要：多选时正文位置显示条数，元信息行给可执行的批量动作
    public static func content(count: Int) -> ClipboardDetailStrip.Content {
        ClipboardDetailStrip.Content(body: "已选 \(count) 条",
                                     meta: "⌘⌫ 删除选中 · Esc 取消多选",
                                     isEmpty: false)
    }

    /// 批量删除的二次确认提示（首次按下只提示，窗口内再按一次才执行）
    public static func deleteConfirmHint(count: Int) -> String {
        "再按一次 ⌘⌫ 删除选中的 \(count) 条"
    }

    /// 批量删除成功后的提示
    public static func deletedHint(count: Int) -> String {
        "已删除 \(count) 条"
    }
}
