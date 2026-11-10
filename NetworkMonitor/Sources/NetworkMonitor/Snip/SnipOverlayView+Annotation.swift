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
        needsDisplay = true
    }

    /// 工具条请求二级面板：关掉已有的，再在触发按钮上方摆出新的
    func toolBarDidRequestPanel(_ content: SnipPanelContent, anchor: CGRect) {
        // 工具条的 frame 由 draw 阶段摆放：先跑一次布局，面板才能贴着真实的工具条定位
        // （否则首次弹出时工具条 frame 还是零尺寸，面板会飘到屏幕左上角）
        layoutToolBar()
        closeToolPanel()
        let panel = SnipToolPanelView(content: content,
                                      selectedIndex: selectedIndex(in: content))
        panel.onPick = { [weak self] index in
            self?.pickPanelItem(in: content, index: index)
        }
        let width = content.size.width
        let height = content.size.height
        // anchor 是工具条自身的本地坐标，面板是覆盖层的子视图：先换算到覆盖层坐标再居中
        let barOriginX = toolbarView?.frame.minX ?? 0
        var originX = barOriginX + anchor.midX - width / 2
        originX = min(max(originX, 8), max(bounds.width - width - 8, 8))
        // 默认贴在一级工具条上方；上方放不下就压到工具条下方
        var originY = (toolbarView?.frame.minY ?? anchor.minY) - height - 6
        if originY < 8 {
            originY = (toolbarView?.frame.maxY ?? anchor.maxY) + 6
        }
        originY = min(max(originY, 8), max(bounds.height - height - 8, 8))
        panel.frame = CGRect(x: originX, y: originY, width: width, height: height)
        addSubview(panel)
        toolPanel = panel
        needsDisplay = true
    }

    /// 二级面板里当前应高亮的项：工具按工具枚举、颜色按色值、线宽按当前宽度
    private func selectedIndex(in content: SnipPanelContent) -> Int? {
        switch content {
        case .tools(let tools):
            guard let activeTool else { return nil }
            return tools.firstIndex(of: activeTool)
        case .colors(let colors):
            return colors.firstIndex(of: currentStyle.color)
        case .widths(let widths):
            return widths.firstIndex(of: currentStyle.lineWidth)
        }
    }

    /// 选中二级面板里的一项：工具 / 颜色 / 线宽各自回写，随后面板收起
    private func pickPanelItem(in content: SnipPanelContent, index: Int) {
        switch content {
        case .tools(let tools):
            guard tools.indices.contains(index) else { closeToolPanel(); return }
            let picked = tools[index]
            activeTool = (activeTool == picked) ? nil : picked
            toolBarDidChangeTool(activeTool)
        case .colors(let colors):
            guard colors.indices.contains(index) else { closeToolPanel(); return }
            currentStyle.color = colors[index]
            toolBarDidChangeStyle(currentStyle)
        case .widths(let widths):
            guard widths.indices.contains(index) else { closeToolPanel(); return }
            currentStyle.lineWidth = widths[index]
            toolBarDidChangeStyle(currentStyle)
        }
        closeToolPanel()
    }

    /// 收起二级面板
    func closeToolPanel() {
        toolPanel?.removeFromSuperview()
        toolPanel = nil
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

    func handleAnnotationMouseDragged(to point: CGPoint) -> Bool {
        if activeTool == .eraser, state.phase == .selected {
            eraseAnnotation(at: point)
            return true
        }
        guard var draft = draftAnnotation else { return false }
        draft.end = point
        if draft.kind == .freehand {
            draft.points.append(point)
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
