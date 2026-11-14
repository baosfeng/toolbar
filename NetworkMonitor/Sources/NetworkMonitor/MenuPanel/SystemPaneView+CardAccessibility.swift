import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 整卡的无障碍上报（从 SystemPaneView+CardView.swift 拆出）

/// 整卡的子元素台账 —— 卡头按钮与内容读数在无障碍树里各是一个元素
///
/// 存储是值类型、挂在卡片实例上（Swift 扩展不能声明存储属性）：
/// 台账本身放在这里，卡里只留一个 `accessibilityElements` 属性。
struct DrawnCardAccessibilityElements {
    /// 卡头最右端按钮（压力卡的「全部 ›」）
    var action: DrawnRowAccessibilityElement?
    /// 卡内容读数的合订文案（一个 staticText，整卡读屏时不会逐块念）
    var content: DrawnRowAccessibilityElement?
}

/// `SystemCardView` 的无障碍 —— 卡级单元素 + 两个子元素，口径统一走 `DrawnAccessibilityReporter`
///
/// 为什么卡内读数要单独挂一个元素：卡整块是按钮（点进二级详情），若读数只写在卡的 label 上，
/// 读屏进入卡片时就念不出一屏数据；子元素给出内容框与合订文案，读屏能逐项走。
extension SystemCardView {

    /// 重建子元素（卡头按钮变化 / 读屏取树前调用）
    func rebuildAccessibilityElements() {
        accessibilityElements.action = headAction.map { action in
            DrawnAccessibilityReporter.element(role: .button,
                                               label: action.title,
                                               parent: self,
                                               activate: action.activate)
        }
        let text = contentAccessibilityText
        guard !text.isEmpty else {
            accessibilityElements.content = nil
            return
        }
        if let existing = accessibilityElements.content {
            existing.setAccessibilityLabel(text)
        } else {
            accessibilityElements.content = DrawnAccessibilityReporter.element(role: .staticText,
                                                                             label: text,
                                                                             parent: self)
        }
    }

    /// 子元素 + 元素框（自绘元素不是视图，frame 每次取树时现算）
    override func accessibilityChildren() -> [Any]? {
        rebuildAccessibilityElements()
        var elements: [Any] = []
        if let action = accessibilityElements.action {
            action.setAccessibilityFrame(
                DrawnAccessibilityReporter.screenFrame(of: headActionRect, in: self))
            elements.append(action)
        }
        if let content = accessibilityElements.content {
            content.setAccessibilityFrame(
                DrawnAccessibilityReporter.screenFrame(of: contentRect, in: self))
            elements.append(content)
        }
        return elements.isEmpty ? nil : elements
    }
}
