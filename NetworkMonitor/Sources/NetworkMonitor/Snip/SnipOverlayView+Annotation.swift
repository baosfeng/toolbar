import AppKit
import NetworkMonitorCore

// MARK: - 标注交互与工具条

extension SnipOverlayView: SnipToolBarViewDelegate {

    // MARK: - 工具条回调

    func toolBarDidChangeTool(_ tool: SnipTool?) {
        activeTool = tool
        // 工具条自己点选时 already 设过一次；二级面板选出来时要回灌给它，
        // 否则「更多」按钮的高亮与图标停在旧状态
        toolbarView?.selectedTool = tool
        needsDisplay = true
    }

    func toolBarDidChangeStyle(_ style: SnipAnnotationStyle) {
        currentStyle = style
        // 一级工具条只显示当前颜色 / 线宽，选完要同步，否则面板里换了色条上看不出来
        toolbarView?.updateStyle(style)
        // 落偏好：下支笔沿用这次的选择（官方口径里这些属于持久设置，不是一次性的）
        onStylePersist?(style)
        needsDisplay = true
    }

    /// 工具条右侧动作按钮（取消 / 复制 / 保存 / 贴顶）
    ///
    /// 此前只有键盘能触发这些动作，鼠标用户看不到任何按钮，
    /// 于是「菜单栏点一下就能确定 / 保存 / 置顶」的需求完全落空。
    func toolBarDidPerform(_ action: SnipBarAction) {
        switch action {
        case .cancel: delegate?.overlayViewDidCancel(self)
        case .copy: confirm()
        case .save: requestSave(quick: false)
        case .pin: requestPin()
        }
    }

    // MARK: - 工具条布局

    /// 选中态才显示工具条：默认贴选区下方居中，放不下就翻到上方
    func layoutToolBar() {
        guard let bar = toolbarView else { return }
        guard toolbarVisible, let selection = state.selection else {
            bar.isHidden = true
            return
        }
        bar.isHidden = false
        let width = SnipToolBarView.preferredWidth
        var originX = selection.midX - width / 2
        originX = min(max(originX, 8), max(bounds.width - width - 8, 8))
        var originY = selection.maxY + 8
        if originY + SnipToolBarView.height > bounds.height - 8 {
            originY = selection.minY - SnipToolBarView.height - 8
        }
        originY = min(max(originY, 8), max(bounds.height - SnipToolBarView.height - 8, 8))
        let frame = CGRect(x: originX, y: originY, width: width, height: SnipToolBarView.height)
        if bar.frame != frame {
            bar.frame = frame
        }
    }

    // MARK: - 绘制

    /// 在选区裁剪区内绘制已完成与正在绘制的标注
    func drawAnnotations(in context: CGContext, clip: CGRect) {
        guard !annotationStack.annotations.isEmpty || draftAnnotation != nil else { return }
        context.saveGState()
        context.clip(to: clip)
        let scale = CGFloat(screenshot.width) / max(bounds.width, 1)
        SnipAnnotationCompositor.draw(annotations: annotationStack.annotations,
                                      base: screenshot,
                                      baseOrigin: displayOrigin,
                                      scale: scale,
                                      in: context)
        if let draft = draftAnnotation {
            SnipAnnotationCompositor.draw(annotations: [draft],
                                          base: screenshot,
                                          baseOrigin: displayOrigin,
                                          scale: scale,
                                          in: context)
        }
        context.restoreGState()
    }

    // MARK: - 鼠标

    func handleAnnotationMouseDown(at point: CGPoint) -> Bool {
        guard let tool = activeTool,
              state.phase == .selected,
              let selection = state.selection,
              selection.contains(point) else {
            return false
        }
        if tool == .eraser {
            eraseAnnotation(at: point)
            return true
        }
        if tool == .polyline {
            if var draft = draftAnnotation {
                draft.points.append(point)
                draft.end = point
                draftAnnotation = draft
            } else {
                draftAnnotation = SnipAnnotation(kind: .polyline,
                                                 start: point,
                                                 end: point,
                                                 points: [point],
                                                 style: currentStyle)
            }
            needsDisplay = true
            return true
        }
        guard let kind = tool.annotationKind else { return false }
        // 二次编辑最小集：点在同类型的已绘制图形上 → 选中它（Del 删除、可见选中描边），
        // 而不是又压一个新图形上去。官方口径是「选中某一类型时对同类型形状二次编辑」。
        if selectSameKindAnnotationIfHit(at: point, kind: kind) { return true }
        if kind == .text {
            // 点在已有文字上 → 选中它（滚轮改字号、⌘R 旋转）；点在空白 → 新建
            if let index = annotationStack.annotations.indices.last(where: {
                annotationStack.annotations[$0].kind == .text
                    && SnipAnnotationRenderer.hitTest(annotationStack.annotations[$0], point: point)
            }) {
                selectedAnnotationIndex = index
                needsDisplay = true
                return true
            }
            beginTextEditing(at: point)
            return true
        }
        draftAnnotation = SnipAnnotation(kind: kind, start: point, end: point, style: currentStyle)
        needsDisplay = true
        return true
    }

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
        textEditor = field
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    @objc func commitTextEditing() {
        guard let field = textEditor else { return }
        let content = field.stringValue
        field.removeFromSuperview()
        textEditor = nil
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
        textEditor = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func handleAnnotationMouseDragged(to point: CGPoint, lockingShift: Bool = false) -> Bool {
        if activeTool == .eraser, state.phase == .selected {
            eraseAnnotation(at: point)
            return true
        }
        guard var draft = draftAnnotation else { return false }
        // Shift 约束：矩形→正方形、椭圆→圆、直线/箭头→水平·垂直·45°、画笔→直线。
        // 约束在每次拖拽都重算（中途按下 Shift 立刻生效、松开立刻回到自由形状），
        // 因此这里用 draft.start 当锚点，不受上一次约束结果影响。
        let constrained = SnipAnnotationConstraint.constrained(kind: draft.kind,
                                                              start: draft.start,
                                                              end: point,
                                                              lockingShift: lockingShift)
        draft.end = constrained
        if draft.kind == .freehand {
            // 画笔轨迹：按住 Shift 时只保留起点与当前点（等于画直线），
            // 否则按历史点追加，中途松手再按住也能延续同一条轨迹
            if lockingShift {
                draft.points = [draft.start, constrained]
            } else {
                draft.points.append(point)
            }
        }
        draftAnnotation = draft
        needsDisplay = true
        return true
    }

    /// 折线不因松手结束，等回车提交
    func finishPolylineDraft() -> Bool {
        guard let draft = draftAnnotation, draft.kind == .polyline else { return false }
        draftAnnotation = nil
        if draft.points.count >= 2 {
            annotationStack.add(draft)
        }
        needsDisplay = true
        return true
    }

    func handleAnnotationMouseUp() -> Bool {
        guard let draft = draftAnnotation else { return false }
        if draft.kind == .polyline { return true }
        draftAnnotation = nil
        if !draft.isDegenerate() {
            annotationStack.add(draft)
        }
        needsDisplay = true
        return true
    }

    /// 旋转选中的文字 90°
    func rotateSelectedAnnotation() {
        guard let index = selectedAnnotationIndex,
              annotationStack.annotations.indices.contains(index) else { return }
        var annotation = annotationStack.annotations[index]
        annotation.rotation = (annotation.rotation + .pi / 2).truncatingRemainder(dividingBy: .pi * 2)
        annotationStack.replace(at: index, with: annotation)
        needsDisplay = true
    }

    /// 橡皮擦：删掉命中的最后一条标注
    func eraseAnnotation(at point: CGPoint) {
        for index in annotationStack.annotations.indices.reversed() {
            let annotation = annotationStack.annotations[index]
            // 轨迹类图元：擦掉命中点附近的一小段，而不是整条删除
            if annotation.kind == .freehand || annotation.kind == .polyline,
               let hit = SnipAnnotationRenderer.nearestPointIndex(in: annotation.points,
                                                                  to: point,
                                                                  tolerance: 10) {
                var updated = annotation
                let lower = max(0, hit - 1)
                let upper = min(updated.points.count, hit + 2)
                updated.points.removeSubrange(lower..<upper)
                if updated.points.count < 2 {
                    annotationStack.remove(at: index)
                } else {
                    updated.start = updated.points.first ?? updated.start
                    updated.end = updated.points.last ?? updated.end
                    annotationStack.replace(at: index, with: updated)
                }
                needsDisplay = true
                return
            }
            if SnipAnnotationRenderer.hitTest(annotation, point: point, tolerance: 10) {
                annotationStack.remove(at: index)
                needsDisplay = true
                return
            }
        }
    }

    /// 当前选区上的标注（供导出合成）
    var annotationsForComposition: [SnipAnnotation] {
        annotationStack.annotations
    }
}