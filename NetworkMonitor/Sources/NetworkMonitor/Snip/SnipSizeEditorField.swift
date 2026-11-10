import AppKit

// MARK: - 输入框（尺寸 / 文字共用）

/// 覆盖层里的单行输入框 — 回车提交，Esc 取消
///
/// Esc 走的是 cancelOperation(_:) 而不是 keyDown：AppKit 会先把 Esc 当作「取消」链路，
/// 只有覆写 cancelOperation 才能在输入框里真的拦到它。keyDown 里再按 keyCode 53 判一次，
/// 是为了兜住从 CGEventTap 兜底路径构造出来的事件（那条路径不经过取消链路）。
/// 从 SnipOverlayView 拆出（主文件贴近单文件 15 KiB 门禁）。
@MainActor
final class SizeEditorField: NSTextField {

    /// 用户按 Esc
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}
