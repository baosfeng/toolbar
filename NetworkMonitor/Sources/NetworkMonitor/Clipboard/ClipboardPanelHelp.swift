import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板页脚文案与浮层显隐

/// 从 ClipboardPanelView+Subviews 拆出：子视图构建与「文案口径 / 浮层开合」是两件事，
/// 混在一个文件里会让后者每次都跟着前者一起长。

/// 底部件数统计文案 — 纯字符串规则，语义与读屏口径各一份
enum ClipboardPanelFooterText {
    /// 可见文案「N 条 · 收藏 M」
    static func countsLabel(total: Int, pinned: Int) -> String {
        "\(total) 条 · 收藏 \(pinned)"
    }

    /// 读屏文案「共 N 条，其中收藏 M 条」
    static func countsAccessibilityLabel(total: Int, pinned: Int) -> String {
        "共 \(total) 条，其中收藏 \(pinned) 条"
    }
}

// MARK: - 快捷键帮助浮层显隐

/// 帮助浮层的开合放在这里：面板视图只负责绘制与布局，显隐口径集中一处
extension ClipboardPanelView {

    /// 帮助浮层是否可见
    var isShortcutHelpVisible: Bool { !helpOverlay.isHidden }

    /// 弹出帮助浮层：不 makeFirstResponder，搜索框焦点不丢（面板本就是非激活面板）
    func showShortcutHelp() {
        helpOverlay.isHidden = false
        // 浮层与父视图都要重排：浮层铺满内容区、卡片按当前尺寸居中
        helpOverlay.needsLayout = true
        needsLayout = true
    }

    /// 收起帮助浮层；返回是否真的收起过（供控制器判断 Esc 是否已被消费）
    @discardableResult
    func hideShortcutHelp() -> Bool {
        guard !helpOverlay.isHidden else { return false }
        helpOverlay.isHidden = true
        return true
    }
}
