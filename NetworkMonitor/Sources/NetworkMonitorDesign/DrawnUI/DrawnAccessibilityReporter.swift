import AppKit

// MARK: - 自绘元素的无障碍上报

/// 自绘子元素 —— 让 VoiceOver 能把「不是视图的东西」（行 / 卡头按钮 / 内容读数）当元素读出来
///
/// 自绘视图的 `accessibilityChildren()` 可以返回任意 `NSAccessibilityElement`：
/// 它没有视图、没有图层，只带 role / label / frame 与一个按下动作。
public final class DrawnRowAccessibilityElement: NSAccessibilityElement {

    /// 元素被按下时执行的动作（nil = 只读元素）
    public var activate: (() -> Void)?

    public override func accessibilityPerformPress() -> Bool {
        guard let activate else { return false }
        activate()
        return true
    }
}

/// 自绘元素上报 —— 两种模式集中在这一处
///
/// - **卡级单元素**：整卡就是一个无障碍节点（剪贴板卡片；视图自己当元素，`accessibilityPerformPress` 即单击）
/// - **子元素多元素**：卡 / 列表里再挂若干元素（行列表的每一行、卡头按钮、卡内容读数）
///
/// 元素 frame 一律按「每次读取时现算」处理：自绘元素不是视图，不会跟着布局自动更新，
/// 所以 `accessibilityChildren()` 每次都要把视图内矩形换算成屏幕矩形重新赋给元素。
@MainActor
public enum DrawnAccessibilityReporter {

    /// 卡级单元素模式：把视图本身配成无障碍节点
    ///
    /// - Parameters:
    ///   - view: 自绘视图（整卡）
    ///   - role: 角色（可点整卡 = .button，纯展示分组 = .group）
    ///   - label: 可读名（nil = 不改，留给内容刷新时逐条更新）
    ///   - value: 状态值（同上）
    public static func configure(_ view: NSView, role: NSAccessibility.Role,
                          label: String? = nil, value: String? = nil) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(role)
        if let label { view.setAccessibilityLabel(label) }
        if let value { view.setAccessibilityValue(value) }
    }

    /// 卡级单元素模式：只改角色（整卡从「组」变「按钮」这类运行时切换）
    public static func setRole(_ role: NSAccessibility.Role, for view: NSView) {
        view.setAccessibilityRole(role)
    }

    /// 子元素：造一个带 parent / role / label 的元素，需要可按下就带动作
    ///
    /// - Parameters:
    ///   - role: 元素角色（可点击 = .button，只读 = .staticText）
    ///   - label: 可读名
    ///   - parent: 归属视图
    ///   - activate: 按下动作（nil = 只读）
    public static func element(role: NSAccessibility.Role, label: String, parent: NSView,
                        activate: (() -> Void)? = nil) -> DrawnRowAccessibilityElement {
        let element = DrawnRowAccessibilityElement()
        element.setAccessibilityParent(parent)
        element.setAccessibilityRole(role)
        element.setAccessibilityLabel(label)
        element.activate = activate
        return element
    }

    /// 视图内矩形 → 屏幕矩形（自绘元素的 frame 口径；无窗口时按视图坐标交回）
    public static func screenFrame(of rect: CGRect, in view: NSView) -> CGRect {
        guard let window = view.window else { return rect }
        return window.convertToScreen(view.convert(rect, to: nil))
    }
}
