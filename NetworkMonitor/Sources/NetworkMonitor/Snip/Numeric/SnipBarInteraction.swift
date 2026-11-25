import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条交互（点击 / 滚轮 / 双击复位）

/// 工具条上的鼠标交互 —— 从 SnipToolBarView 主文件拆出
///
/// 拆出的理由与规矩一致：`SnipToolBarView` 族已有三个文件，同族合计门禁只允许变小。
/// 交互与排版是两件独立的事（一个判命中、一个算矩形），混在一个文件里两边都长。
/// 文件名不带 `SnipToolBarView` 前缀，因此单独成族、不占工具条族的额度。
extension SnipToolBarView {

    /// 数值按钮（当前色 / 当前线宽）上滚动 = 直接调那个数值
    ///
    /// Snipaste 的口径是「指针停在大颜色按钮上滚轮调透明度」—— 靠控件命中而不是修饰键。
    /// 我们补上同一条：指到线宽 / 字号按钮上滚，调的就是它，不必先点开面板。
    /// 其余位置的滚轮不在这里消费（返回给覆盖层走工具 / 缩放分流）。
    override func scrollWheel(with event: NSEvent) {
        // 判定（哪颗按钮代表哪个参数 / 滚了几格 / 什么意图）交给 SnipBarNumericInteraction，
        // 这里只留转发，视图不再长身体
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = item(at: point),
              let param = SnipBarNumericInteraction.param(for: hit, selectedTool: selectedTool) else {
            super.scrollWheel(with: event)
            return
        }
        let steps = SnipBarNumericInteraction.steps(for: event, stepper: &numericScrollAccumulator)
        guard steps != 0 else { return }
        delegate?.toolBarDidScrollNumeric(param, steps: steps,
                                          intent: SnipBarNumericInteraction.intent(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 置灰的动作不响应点击（item(at:) 已按可用性过滤，这里再兜一层）
        guard let hit = item(at: point), isEnabled(hit) else { return }
        // 双击数值按钮 = 复位（Snipaste / Lightroom 的通用约定：双击回到默认值）
        // 只有数值按钮吃双击；工具与动作按钮照旧，双击等于点两次不会误复位。
        if event.clickCount == 2, let param = SnipBarNumericInteraction.param(for: hit,
                                                                           selectedTool: selectedTool) {
            delegate?.toolBarDidResetNumeric(param)
            return
        }
        switch hit {
        case .tool(let tool):
            selectedTool = (selectedTool == tool) ? nil : tool
            delegate?.toolBarDidChangeTool(selectedTool)
        case .more:
            delegate?.toolBarDidRequestPanel(.tools(configuration.overflowTools), anchor: visibleRect(of: hit))
        case .color:
            delegate?.toolBarDidRequestPanel(.colors(Self.colors), anchor: visibleRect(of: hit))
        case .width:
            // 选中文字工具时这个入口弹的是「文字样式」（字号 / 加粗 / 字体），
            // 其余情况才是画笔样式（线宽 / 虚线 / 颜色 Alpha）。
            // 为什么不拆成两个按钮：文字标注时线宽对结果几乎无影响，而字号是刚需，
            // 复用同一个入口让工具条保持 4 个高频工具 + 4 个动作的既有宽度。
            if selectedTool == .text {
                delegate?.toolBarDidRequestPanel(.textStyles(sizes: SnipTextStyle.fontSizePresets,
                                                             bold: style.text.bold,
                                                             family: style.text.family),
                                                 anchor: visibleRect(of: hit))
            } else {
                delegate?.toolBarDidRequestPanel(.styles(widths: Self.widths,
                                                         dashes: Self.dashes,
                                                         alphas: Self.alphas),
                                                 anchor: visibleRect(of: hit))
            }
        case .action(let action):
            delegate?.toolBarDidPerform(action)
        }
    }

    /// 命中项在「可视条坐标」里的矩形（覆盖层按它定位二级面板，不含气泡区偏移）
    private func visibleRect(of item: SnipBarItem) -> CGRect {
        let rect = itemRects.first { $0.item == item }?.rect ?? .zero
        return rect.offsetBy(dx: -barOriginX, dy: -barOriginY)
    }
}
