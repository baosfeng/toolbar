import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 数值读数与精确输入（控制器的一部分）

/// 读数气泡的显示 / 淡出，以及就地输入框的弹出与提交
///
/// 与 SnipNumericController 拆成两个文件：一个管「调的时候看得见」，一个管「调不准时打字」，
/// 两者的生命周期与失败模式都不一样（前者是纯反馈、后者要走键盘焦点），合在一起会让
/// 单文件与同族门禁同时告警。
extension SnipNumericController {

    // MARK: - 读数气泡

    /// 显示（或刷新）数值读数
    ///
    /// 连续调整时只更新文字、不重建视图、不重开淡出计时器的「显示中」状态 ——
    /// 否则每格滚轮都重新入场，用户看到的是持续闪动而不是一个稳定的读数。
    func showHUD(_ param: SnipNumericParam,
                 intent: SnipNumericIntent,
                 overrideValue: CGFloat? = nil) {
        guard let host = hostView() else { return }
        let entry = SnipNumericHUD.Entry(param: param,
                                         value: overrideValue ?? value(of: param),
                                         intent: intent)
        let view: SnipNumericHUDView
        if let existing = hud {
            view = existing
        } else {
            view = SnipNumericHUDView()
            view.isHidden = true
            host.addSubview(view)
            hud = view
        }
        view.show(entry)
        view.alphaValue = 1
        view.isHidden = false
        // 光标位置用 pointer：它在 mouseMoved / dragged 里一直更新；键盘调整时没有鼠标移动，
        // pointer 仍是用户最后一次停留的位置，正是想要的那个锚点。
        view.frame.origin = SnipNumericHUD.origin(size: view.frame.size,
                                                  cursor: pointerLocation(),
                                                  bounds: viewBounds())
        scheduleDismiss()
    }

    /// 立刻收起读数（取消截图 / 切换工具时调，避免残留一块读数飘在屏上）
    func hideHUD() {
        hudTask?.cancel()
        hudTask = nil
        hud?.isHidden = true
        hud?.clear()
    }

    /// 排一次淡出：1.2s 后淡出 0.25s 再隐藏
    ///
    /// 用 DispatchWorkItem 而不是 Timer：连续调整时 cancel + 重排即可
    /// （Timer 要 invalidate 再重建，且 RunLoop 模式的差异会让它在拖拽期间停摆）。
    private func scheduleDismiss() {
        hudTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, let view = self.hud, !view.isHidden else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SnipNumericHUD.fadeDuration
                view.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, let view = self.hud else { return }
                // 淡出期间若又被调整过（alphaValue 被拉回 1），这次隐藏要作废
                guard view.alphaValue < 0.01 else { return }
                view.isHidden = true
                view.clear()
            }
        }
        hudTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + SnipNumericHUD.visibleDuration,
                                      execute: task)
    }

    // MARK: - 精确输入

    /// 弹数值输入框
    ///
    /// - Parameters:
    ///   - param: 要输入的那个参数
    ///   - anchor: 输入框贴着哪个矩形（覆盖层本地坐标）
    ///   - parent: 覆盖层视图（输入框要挂上去并抢键盘焦点）
    ///   - finish: 收尾回调（覆盖层要把输入框从「编辑态」登记里摘掉）
    func beginEditing(_ param: SnipNumericParam,
                      anchor: CGRect,
                      parent: SnipOverlayView) {
        guard hasSelection(), parent.sizeEditor == nil else { return }
        let field = SizeEditorField(frame: CGRect(x: anchor.minX,
                                                  y: anchor.maxY + 4,
                                                  width: 96,
                                                  height: 22))
        field.stringValue = param.format(value(of: param))
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.alignment = .center
        field.setAccessibilityLabel(param.displayName + "精确输入")
        field.target = self
        field.action = #selector(commitEditingFromField(_:))
        field.onCancel = { [weak self] in self?.endEditing(apply: false) }
        session.editingParam = param
        parent.addSubview(field)
        parent.replaceSizeEditor(field)
        parent.window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    /// 输入框回车
    @objc private func commitEditingFromField(_ sender: Any?) {
        endEditing(apply: true)
    }

    /// 收尾：apply 为真时解析并写入
    func endEditing(apply: Bool) {
        guard let parent = hostView() as? SnipOverlayView,
              let field = parent.sizeEditor,
              let param = session.editingParam else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        parent.replaceSizeEditor(nil)
        session.editingParam = nil
        parent.window?.makeFirstResponder(parent)
        guard apply, let parsed = SnipNumericInput.parse(text, param: param) else { return }
        assign(param, value: parsed)
    }
}
