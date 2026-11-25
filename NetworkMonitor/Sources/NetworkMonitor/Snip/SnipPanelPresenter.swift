import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 二级面板（工具 / 颜色 / 画笔样式 / 文字样式）

/// 工具条「更多 / 当前色 / 当前线宽」三个入口弹出的面板：创建、定位、选中回写、收起
///
/// 从 SnipOverlayView+Annotation.swift 拆出：主文件同时装着标注交互与工具条布局，
/// 逼近单文件 15 KiB 门禁。这里只做「把面板摆出来、把点中的项写回样式」这一件事。
extension SnipOverlayView {


    /// 工具条请求二级面板：关掉已有的，再在触发按钮上方摆出新的
    func toolBarDidRequestPanel(_ content: SnipPanelContent, anchor: CGRect) {
        // 工具条的 frame 由 draw 阶段摆放：先跑一次布局，面板才能贴着真实的工具条定位
        // （否则首次弹出时工具条 frame 还是零尺寸，面板会飘到屏幕左上角）
        layoutToolBar()
        closeToolPanel()
        // 面板的文字提示档与一级工具条同源：设置页选了「常驻标签」面板也跟着带标签
        let labelMode = toolbarView?.configuration.labelMode ?? .hover
        let panel = SnipToolPanelView(content: content,
                                      selectedIndex: selectedIndex(in: content),
                                      labelMode: labelMode)
        panel.onPick = { [weak self] index in
            self?.pickPanelItem(in: content, index: index, anchor: anchor)
        }
        let size = content.size(labelMode: labelMode)
        let width = size.width
        let height = size.height
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
        // 面板展开期间不画工具条气泡：气泡位置正好被面板盖住
        toolbarView?.isPanelOpen = true
        needsDisplay = true
    }

    /// 二级面板里当前应高亮的项：工具按工具枚举、颜色按色值、线宽按当前宽度
    ///
    /// 高亮只挑**一个**格子：线宽 / 虚线 / 透明度三个维度都可能命中同一个盘面，
    /// 同时加环会让用户以为它们是同一个参数。优先级按「最常调」排：线宽 → 虚线 → 透明度。
    private func selectedIndex(in content: SnipPanelContent) -> Int? {
        switch content {
        case .tools(let tools):
            guard let activeTool else { return nil }
            return tools.firstIndex(of: activeTool)
        case .colors(let colors):
            return colors.firstIndex(of: currentStyle.color)
        case .widths(let widths):
            return widths.firstIndex(of: currentStyle.lineWidth)
        case .styles(let widths, let dashes, let alphas):
            // 线宽不吸附档位（连续值），只有恰好等于某个档位时才点亮那一格
            if widths.contains(currentStyle.lineWidth) {
                return widths.firstIndex(of: currentStyle.lineWidth)
            }
            if let dash = dashes.firstIndex(of: currentStyle.dashed) {
                return widths.count + SnipPanelContent.stylesStepCount + dash
            }
            guard let alpha = alphas.firstIndex(where: { abs($0 - currentStyle.color.alpha) < 0.01 }) else {
                return nil
            }
            return widths.count + SnipPanelContent.stylesStepCount + dashes.count + alpha
        case .textStyles(let sizes, let bold, _):
            // 字号：当前值等于某个档位才点亮；加粗与字体族各自一格
            if let size = sizes.firstIndex(where: { abs($0 - (currentStyle.text.fontSize ?? 0)) < 0.01 }) {
                return size
            }
            if bold != currentStyle.text.bold { return nil }
            let familyIndex = SnipTextFamily.allCases.firstIndex(of: currentStyle.text.family) ?? 0
            return sizes.count + 1 + familyIndex
        }
    }

    /// 选中二级面板里的一项：工具 / 颜色 / 线宽各自回写，随后面板收起
    private func pickPanelItem(in content: SnipPanelContent, index: Int, anchor: CGRect) {
        switch content {
        case .tools(let tools):
            guard tools.indices.contains(index) else { closeToolPanel(); return }
            let picked = tools[index]
            activeTool = (activeTool == picked) ? nil : picked
            toolBarDidChangeTool(activeTool)
        case .colors(let colors):
            if index == colors.count {
                // 末尾一格 = 自定义：收起色盘，原地弹出自绘取色板
                openColorPicker(anchor: anchor, replacingPanel: true)
                return
            }
            guard colors.indices.contains(index) else { closeToolPanel(); return }
            // 换色时保留当前透明度：用户调好的半透明不该因为换个色相就被重置
            currentStyle.color = colors[index].withAlpha(currentStyle.color.alpha)
            toolBarDidChangeStyle(currentStyle)
        case .widths(let widths):
            guard widths.indices.contains(index) else { closeToolPanel(); return }
            currentStyle.lineWidth = widths[index]
            toolBarDidChangeStyle(currentStyle)
        case .styles(let widths, let dashes, let alphas):
            // 末尾「输入…」格：就地弹输入框，面板收起（输入框要独占键盘）
            if content.numericInputSlotIndex == index {
                // 输入框贴在面板原来的位置（面板坐标即覆盖层坐标，两者是兄弟子视图）
                let panelFrame = toolPanel?.frame ?? .zero
                closeToolPanel()
                numeric.beginEditing(.lineWidth, anchor: panelFrame, parent: self)
                return
            }
            applyStylePanelItem(widths: widths, dashes: dashes, alphas: alphas, index: index)
            // 样式面板是可多次调整的盘面，不像工具/颜色那样点一次就收起
            return
        case .textStyles(let sizes, let bold, let family):
            applyTextStylePanelItem(sizes: sizes, bold: bold, family: family, index: index)
            // 文字盘同理：调字号往往要点好几下
            return
        }
        closeToolPanel()
    }

    /// 样式面板单项回写：线宽 / 虚线 / 颜色透明度
    ///
    /// 三件事都可能改到 currentStyle，统一走 toolBarDidChangeStyle 回灌工具条，
    /// 并落偏好（annotationLineWidth / annotationDashed / annotationColor），
    /// 让「这次调的样式」下次截图还是它 —— 官方口径是这些属于持久偏好。
    private func applyStylePanelItem(widths: [CGFloat],
                                     dashes: [Bool],
                                     alphas: [CGFloat],
                                     index: Int) {
        if widths.indices.contains(index) {
            // 档位格只是快捷项：点它 = 把线宽设成这个值（与滚轮/按键同一条写入路径）
            _ = numeric.assign(.lineWidth, value: widths[index], showsHUD: false)
        } else {
            let afterWidths = index - widths.count
            if afterWidths < SnipPanelContent.stylesStepCount {
                // −/+ 连续微调：在任意线宽上按 1pt 走，不吸附档位
                _ = numeric.adjust(.lineWidth, steps: afterWidths == 0 ? -1 : 1, intent: .coarse)
            } else {
                let offset = afterWidths - SnipPanelContent.stylesStepCount
                if dashes.indices.contains(offset) {
                    currentStyle.dashed = dashes[offset]
                } else {
                    let alphaIndex = offset - dashes.count
                    if alphas.indices.contains(alphaIndex) {
                        // 透明度只改颜色的 alpha 分量，RGB 保持用户选的那支色。
                        // 走 assignNumeric 而不是直接写 color：那条路径会夹取量化并弹读数，
                        // 与滚轮 / ⌃+滚轮 是同一条写入路径，不会出现「面板点到 0.3 但显示 30%」这类分叉。
                        _ = numeric.assign(.opacity, value: alphas[alphaIndex], showsHUD: false)
                    }
                }
            }
        }
        toolBarDidChangeStyle(currentStyle)
    }

    /// 文字样式盘单项回写：字号档 / 加粗开关 / 字体族
    ///
    /// 字号档里跟了一个「当前值」的隐式规则：点档位 = 把基准字号设成该档，
    /// 之后滚轮仍可在这条标注上做临时缩放（fontScale 是另一层）。
    private func applyTextStylePanelItem(sizes: [CGFloat],
                                         bold: Bool,
                                         family: SnipTextFamily,
                                         index: Int) {
        if sizes.indices.contains(index) {
            // 字号档同理：点它 = 把基准字号设成该值（与 0/9 键、滚轮同一条路径）
            _ = numeric.assign(.fontSize, value: sizes[index], showsHUD: false)
        } else if index == sizes.count {
            currentStyle.text.bold.toggle()
        } else {
            let familyIndex = index - sizes.count - 1
            let families = SnipTextFamily.allCases
            if families.indices.contains(familyIndex) {
                currentStyle.text.family = families[familyIndex]
            }
        }
        toolBarDidChangeStyle(currentStyle)
    }

    /// 弹出 / 收起自绘取色板
    ///
    /// 取色板独占一层：色盘与画笔盘都不跟着它显示（同屏两块面板会互相遮挡，
    /// 而取色这件事本来就要一块尽可能大的区域）。
    func openColorPicker(anchor: CGRect, replacingPanel: Bool) {
        layoutToolBar()
        if replacingPanel { closeToolPanel() }
        closeColorPicker()
        let picker = SnipColorPickerView(color: currentStyle.color)
        picker.onColorChanged = { [weak self] color in
            guard let self else { return }
            currentStyle.color = color
            // 颜色拖动过程中就实时回写工具条与选中项：松手才变会让人觉得卡
            toolBarDidChangeStyle(currentStyle)
            applyStyleToSelectedAnnotation { annotation in
                annotation.style.color = currentStyle.color
            }
        }
        picker.onClose = { [weak self] in self?.closeColorPicker() }
        let size = SnipColorPickerView.panelSize
        let barOriginX = toolbarView?.frame.minX ?? 0
        var originX = barOriginX + anchor.midX - size.width / 2
        originX = min(max(originX, 8), max(bounds.width - size.width - 8, 8))
        var originY = (toolbarView?.frame.minY ?? anchor.minY) - size.height - 6
        if originY < 8 {
            originY = (toolbarView?.frame.maxY ?? anchor.maxY) + 6
        }
        originY = min(max(originY, 8), max(bounds.height - size.height - 8, 8))
        picker.frame = CGRect(x: originX, y: originY, width: size.width, height: size.height)
        addSubview(picker)
        colorPicker = picker
        needsDisplay = true
    }

    /// 收起取色板
    func closeColorPicker() {
        colorPicker?.removeFromSuperview()
        colorPicker = nil
        needsDisplay = true
    }

    /// 收起二级面板
    func closeToolPanel() {
        toolPanel?.removeFromSuperview()
        toolPanel = nil
        // 面板收掉后恢复气泡：用户还停在按钮上时仍能看到名称
        toolbarView?.isPanelOpen = false
        needsDisplay = true
    }
}
