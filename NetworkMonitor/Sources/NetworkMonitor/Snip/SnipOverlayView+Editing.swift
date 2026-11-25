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

    // MARK: - 撤销 / 重做（键盘与工具条的唯一实现）

    /// 撤销最后一条标注：⌘Z 与工具条「撤销」按钮共用这一份实现
    func performUndo() {
        guard annotationStack.canUndo else { return }
        annotationStack.undo()
        needsDisplay = true
    }

    /// 重做刚撤销的一条：⌘Y 与工具条「重做」按钮都走这里
    func performRedo() {
        guard annotationStack.canRedo else { return }
        annotationStack.redo()
        needsDisplay = true
    }

    /// 把标注栈的可用性灌给工具条（栈每次变化都调一次）
    func syncAnnotationAvailability() {
        toolbarView?.annotationAvailability = SnipBarActionAvailability(
            canUndo: annotationStack.canUndo,
            canRedo: annotationStack.canRedo)
    }

    // MARK: - 画笔粗细

    /// 步进画笔粗细（线宽这根旋钮的唯一入口）
    ///
    /// 交给 SnipNumeric 统一处理：连续步进（不再吸附 [2,4,8]）、落偏好、
    /// 同步到选中图形、弹数值读数 —— 四件事此前一件都没做对。
    @discardableResult
    func stepLineWidth(by delta: Int, intent: SnipNumericIntent = .coarse) -> Bool {
        numeric.adjust(.lineWidth, steps: delta, intent: intent)
    }

    /// 调整文字字号：没有显式字号时从「线宽推导出来的那个值」起跳
    ///
    /// 返回 true 表示真的改了（调用方据此决定按键是否放行）。
    /// 步进口径交给 SnipNumeric：字号过去按「当前字号的 10%」步进（小字 1pt、大字 4pt），
    /// 同样是按一次键，行为跟着字号大小变 —— 用户没法建立肌肉记忆。
    @discardableResult
    func adjustTextFontSize(by delta: Int, intent: SnipNumericIntent = .coarse) -> Bool {
        guard numeric.adjust(.fontSize, steps: delta, intent: intent) else { return false }
        // 选中了一条文字标注时同步改它：用户按了字号键却看不到变化是最费解的空操作
        applyStyleToSelectedAnnotation { annotation in
            annotation.style.text.fontSize = self.currentStyle.text.fontSize
        }
        return true
    }

    /// 把 currentStyle 的一部分改到当前选中的标注上（样式热更新）
    ///
    /// 二次编辑的最小闭环：选中 → 改样式 → 立刻看见。只改选中项，
    /// 不动其它图元，也不把这次改动作成新的可撤销步骤（撤销栈只记「加了什么」）。
    func applyStyleToSelectedAnnotation(_ mutate: (inout SnipAnnotation) -> Void) {
        guard let index = selectedAnnotationIndex,
              annotationStack.annotations.indices.contains(index) else { return }
        var annotation = annotationStack.annotations[index]
        mutate(&annotation)
        annotationStack.replace(at: index, with: annotation)
        needsDisplay = true
    }

    /// 画笔透明度的唯一入口（⌃+滚轮、面板透明度格、设置页共用）
    @discardableResult
    func stepOpacity(by delta: Int, intent: SnipNumericIntent = .coarse) -> Bool {
        guard numeric.adjust(.opacity, steps: delta, intent: intent) else { return false }
        return true
    }

    // MARK: - 选中与删除

    /// 删除当前选中的标注；返回是否真的删了
    ///
    /// 官方二次编辑的最小集：先能选中、再能删。没有选中内容时返回 false，
    /// 由调用方把按键放行（吞掉一个什么都不做的 Del 比不响应更糟）。
    func deleteSelectedAnnotation() -> Bool {
        guard let index = selectedAnnotationIndex,
              annotationStack.annotations.indices.contains(index) else { return false }
        annotationStack.remove(at: index)
        selectedAnnotationIndex = nil
        needsDisplay = true
        return true
    }

    /// 点中**同类型**的已绘制图形 → 选中它（官方二次编辑语义）
    ///
    /// 只选同类型：选中矩形工具时点箭头不该把箭头选走（那是拖出新矩形的手势）。
    /// 轨迹类（画笔 / 折线）无论如何都让给绘制：它们的命中带比较宽，
    /// 点一下就被选走会让「接着上一笔继续画」变得不可能。
    @discardableResult
    func selectSameKindAnnotationIfHit(at point: CGPoint, kind: SnipAnnotationKind) -> Bool {
        guard draftAnnotation == nil, !kind.isStroke else { return false }
        for index in annotationStack.annotations.indices.reversed() {
            let annotation = annotationStack.annotations[index]
            guard annotation.kind == kind else { continue }
            if SnipAnnotationRenderer.hitTest(annotation, point: point, tolerance: 8) {
                selectedAnnotationIndex = index
                needsDisplay = true
                return true
            }
        }
        return false
    }

    /// 点中已有标注 → 选中它（供 Del 删除与可见的选中描边）
    ///
    /// 只在没有草稿时生效：正在画新图形时点击应继续画，不该被上一个图形抢走。
    /// 命中判定复用渲染器的 hitTest（与橡皮擦同一口径）。
    @discardableResult
    func selectAnnotationIfHit(at point: CGPoint) -> Bool {
        guard draftAnnotation == nil else { return false }
        for index in annotationStack.annotations.indices.reversed() {
            if SnipAnnotationRenderer.hitTest(annotationStack.annotations[index],
                                              point: point,
                                              tolerance: 8) {
                selectedAnnotationIndex = index
                needsDisplay = true
                return true
            }
        }
        if selectedAnnotationIndex != nil {
            selectedAnnotationIndex = nil
            needsDisplay = true
        }
        return false
    }
}
