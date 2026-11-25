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
    ///
    /// - Parameter editing: 传入已存在的标注下标时进入「改文字」而不是「新建」。
    ///   文字标注写错一个字只能删了重画是这个工具最常被抱怨的点之一。
    func beginTextEditing(at point: CGPoint, editing index: Int? = nil) {
        guard textEditor == nil else { return }
        textEditingAnchor = point
        textEditingIndex = index
        let field = SizeEditorField(frame: CGRect(x: point.x, y: point.y, width: 220, height: 24))
        if let index, annotationStack.annotations.indices.contains(index) {
            field.stringValue = annotationStack.annotations[index].text
        } else {
            field.stringValue = ""
        }
        field.placeholderString = "输入文字，回车确认"
        // 输入框字号跟落字字号一致：13pt 的小框里写 40pt 的大字，
        // 用户在输入时看到的是「很小的字」，落字后突然变大，很难预判排版
        field.font = .systemFont(ofSize: min(max(textInputFontSize, 12), 24))
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitTextEditing)
        field.onCancel = { [weak self] in self?.cancelTextEditing() }
        addSubview(field)
        replaceTextEditor(field)
        window?.makeFirstResponder(field)
        field.selectText(nil)
        needsDisplay = true
    }

    /// 输入框里用的字号：跟当前笔的落字字号走，但夹到一个能编辑的区间
    private var textInputFontSize: CGFloat {
        currentStyle.text.fontSize ?? max(currentStyle.lineWidth * 5, 14)
    }

    @objc func commitTextEditing() {
        guard let field = textEditor else { return }
        let content = field.stringValue
        let editingIndex = textEditingIndex
        textEditingIndex = nil
        field.removeFromSuperview()
        replaceTextEditor(nil)
        window?.makeFirstResponder(self)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 改成空 = 删掉这条文字（改文字时把内容清空是一种自然的「删掉」表达）
            if let editingIndex, annotationStack.annotations.indices.contains(editingIndex) {
                annotationStack.remove(at: editingIndex)
                selectedAnnotationIndex = nil
            }
            needsDisplay = true
            return
        }
        if let editingIndex, annotationStack.annotations.indices.contains(editingIndex) {
            // 改文字：保留原有位置、缩放与旋转，只换内容
            var annotation = annotationStack.annotations[editingIndex]
            annotation.text = trimmed
            annotationStack.replace(at: editingIndex, with: annotation)
        } else {
            let annotation = SnipAnnotation(kind: .text,
                                            start: textEditingAnchor,
                                            end: textEditingAnchor,
                                            text: trimmed,
                                            style: currentStyle)
            annotationStack.add(annotation)
        }
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
