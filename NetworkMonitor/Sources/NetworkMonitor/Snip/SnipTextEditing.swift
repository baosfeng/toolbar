import AppKit
import NetworkMonitorCore

// MARK: - 输入框编辑态（文字 / 尺寸共用）

/// 文字输入框的创建、落字与取消
///
/// 从 SnipOverlayView+Annotation 拆出来，与「编辑态信号」放在同一份文件里：
/// 用户报的「点文字工具 → 敲键盘看不到字、退格删不掉」正是这两件事没接上造成的。
/// 编辑态的生产侧（输入框装上 / 卸下）与消费侧（系统层按键通道）必须一起读，改一处就看得见另一处。
extension SnipOverlayView {

    // MARK: - 文字输入

    /// 在点击位置弹出输入框，回车落字
    func beginTextEditing(at point: CGPoint) {
        guard textEditor == nil else { return }
        textEditingAnchor = point
        let field = SizeEditorField(frame: CGRect(x: point.x, y: point.y, width: 220, height: 24))
        field.stringValue = ""
        field.placeholderString = "输入文字，回车确认"
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitTextEditing)
        field.onCancel = { [weak self] in self?.cancelTextEditing() }
        addSubview(field)
        replaceTextEditor(field)
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    @objc func commitTextEditing() {
        guard let field = textEditor else { return }
        let content = field.stringValue
        field.removeFromSuperview()
        replaceTextEditor(nil)
        window?.makeFirstResponder(self)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            needsDisplay = true
            return
        }
        let annotation = SnipAnnotation(kind: .text,
                                        start: textEditingAnchor,
                                        end: textEditingAnchor,
                                        text: trimmed,
                                        style: currentStyle)
        annotationStack.add(annotation)
        needsDisplay = true
    }

    func cancelTextEditing() {
        textEditor?.removeFromSuperview()
        replaceTextEditor(nil)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

}

// MARK: - 编排层接线

extension SnipController {

    /// 输入框（文字 / 尺寸）开始或结束编辑：同步给系统层按键通道
    ///
    /// 多屏时键盘事件本来就只归首屏，因此这里不再区分是哪一屏的输入框。
    func overlayView(_ view: SnipOverlayView, didChangeTextEditing isEditing: Bool) {
        setKeyboardEditing(isEditing)
    }

    /// 输入框开始 / 结束编辑时把编辑态同步给系统层按键通道
    ///
    /// 这是 SnipKeyboardGate 的唯一写入点，由 SnipOverlayView 的编辑态收口处驱动。
    /// 为什么不是「收到键之后再同步」：吞键发生在编辑态被感知之前，任何滞后一拍的写法
    /// 都会让第一个键（往往正是拼音的声母）落在闸门之外。
    func setKeyboardEditing(_ editing: Bool) {
        keyboardBridge?.setEditing(editing)
        logger.debug("截图键盘通道：输入框编辑态 → " + (editing ? "放行" : "接管"))
    }
}
