import AppKit
import NetworkMonitorCore

// MARK: - 二级面板（工具 / 颜色 / 画笔样式）

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
        case .styles(let widths, let dashes, let alphas):
            // 高亮当前同时生效的三项：线宽档、实虚线、颜色透明度（三个都可能命中同一个盘面）
            if let i = widths.firstIndex(of: currentStyle.lineWidth) { return i }
            let dashIndex = widths.count + (dashes.firstIndex(of: currentStyle.dashed) ?? 0)
            if dashes.indices.contains(0) { return dashIndex }
            let alphaIndex = widths.count + dashes.count + (alphas.firstIndex(of: currentStyle.color.alpha) ?? 0)
            return alphas.isEmpty ? nil : alphaIndex
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
        case .styles(let widths, let dashes, let alphas):
            applyStylePanelItem(widths: widths, dashes: dashes, alphas: alphas, index: index)
            // 样式面板是可多次调整的盘面，不像工具/颜色那样点一次就收起
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
            currentStyle.lineWidth = widths[index]
        } else {
            let offset = index - widths.count
            if dashes.indices.contains(offset) {
                currentStyle.dashed = dashes[offset]
            } else {
                let alphaIndex = offset - dashes.count
                if alphas.indices.contains(alphaIndex) {
                    // 透明度只改颜色的 alpha 分量，RGB 保持用户选的那支色
                    currentStyle.color = currentStyle.color.withAlpha(alphas[alphaIndex])
                }
            }
        }
        toolBarDidChangeStyle(currentStyle)
    }

    /// 收起二级面板
    func closeToolPanel() {
        toolPanel?.removeFromSuperview()
        toolPanel = nil
        needsDisplay = true
    }
}
