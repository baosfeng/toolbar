import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 右键语义与画笔粗细（从主类拆出，守住单文件门禁）

extension SnipOverlayView {

    // MARK: - 右键

    /// 右键：编辑态只收笔，非编辑态才中止整次截图
    ///
    /// 官方两张键位表对右键给了不同含义，早期实现一律当成中止：
    /// 用户画到一半按右键会连整张截图一起丢掉（本轮最刺眼的行为偏差）。
    func handleRightClick() {
        switch SnipRightClickIntent.outcome(hasDraft: draftAnnotation != nil,
                                            isTextEditing: hasActiveTextInput,
                                            hasSelectedAnnotation: selectedAnnotationIndex != nil) {
        case .finishAnnotation:
            finishCurrentAnnotation()
        case .cancelSnip:
            delegate?.overlayViewDidCancel(self)
        }
    }

    /// 收笔：文字先落字，草稿按类型提交，选中的标注取消选中；截图与已完成标注都保留
    func finishCurrentAnnotation() {
        if textEditor != nil {
            commitTextEditing()
            return
        }
        // 折线在松手后仍在草稿里（它等回车提交），右键与回车同义
        if finishPolylineDraft() { return }
        if let draft = draftAnnotation {
            draftAnnotation = nil
            if !draft.isDegenerate() {
                annotationStack.add(draft)
            }
        }
        selectedAnnotationIndex = nil
        needsDisplay = true
    }

    // MARK: - 清空所有标注

    /// 移除所有标注并清空撤销 / 重做栈（官方 ⌘⇧Z，不可恢复）
    func clearAllAnnotations() {
        annotationStack.clear()
        draftAnnotation = nil
        selectedAnnotationIndex = nil
        needsDisplay = true
    }

    // MARK: - 画笔粗细

    /// 按档位步进画笔粗细，并回灌一级工具条与二级面板
    func stepLineWidth(by delta: Int) {
        let next = SnipLineWidthStepper.step(from: currentStyle.lineWidth, by: delta)
        guard abs(next - currentStyle.lineWidth) > 0.0001 else { return }
        currentStyle.lineWidth = next
        toolbarView?.updateStyle(currentStyle)
        needsDisplay = true
    }

    /// 标注模式下的滚轮调粗细；返回 true 表示已消费这次滚轮
    ///
    /// 文字字号那条通路优先：选中文字时滚轮仍改字号（早于本函数的判定）。
    func handleStyleScroll(_ event: NSEvent) -> Bool {
        guard selectedAnnotationIndex == nil else { return false }
        guard activeTool != nil, state.phase == .selected else { return false }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return true }
        stepLineWidth(by: delta > 0 ? 1 : -1)
        return true
    }
}
