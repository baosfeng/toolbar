import CoreGraphics

// MARK: - 工具条三档明度与选中语言（纯逻辑，可单测）

/// 工具条「选中 / 悬停 / 常态」三档明度与两级选中语言的唯一真源
///
/// 背景：选中填 `white 0.22`、悬停 `0.14`，差值只有 0.08 —— 小尺寸按钮上
/// 分不出「已选中」与「正悬停」。三档收敛到这里，绘制只读常量，TestRunner 直接断言，
/// 不会再出现「改了绘制、别处还按老值画」。
///
/// 这里只承载**相对明度与选中语言语义**，不含色值 / 字号 / 圆角：
/// 将来要随主题变化时应整体搬进设计系统（NetworkMonitorDesign）且只定义一次，不得两边各存一份。
public enum SnipBarTone {

    // MARK: - 三档填充

    /// 选中格填充：最亮的一档（整格反白）
    public static let selectedFillAlpha: CGFloat = 0.30
    /// 悬停填充：明显低于选中档（差值 0.17 ≥ 0.15），只作「这里可以点」的轻提示
    public static let hoverFillAlpha: CGFloat = 0.13

    // MARK: - 三档图标

    /// 常态图标略压暗
    public static let normalIconAlpha: CGFloat = 0.72
    /// 悬停图标轻微提亮（仍未选中，故不给满白）
    public static let hoverIconAlpha: CGFloat = 0.95
    /// 选中图标：纯白
    public static let selectedIconAlpha: CGFloat = 1

    /// 图标 alpha 三档：选中恒为纯白，悬停轻微提亮，其余略压暗
    public static func iconAlpha(isSelected: Bool, isHovered: Bool) -> CGFloat {
        if isSelected { return selectedIconAlpha }
        return isHovered ? hoverIconAlpha : normalIconAlpha
    }

    /// 填充 alpha 两档：选中最亮、悬停更淡；两档都不成立时返回 `nil`（不画底）
    public static func fillAlpha(isSelected: Bool, isHovered: Bool) -> CGFloat? {
        if isSelected { return selectedFillAlpha }
        return isHovered ? hoverFillAlpha : nil
    }

    // MARK: - 不可用（置灰）档

    /// 动作按钮置灰时的文字 alpha
    ///
    /// 与可用态的常态图标（0.72）拉开到一半以下：截图工具条是黑底，
    /// 0.35 是「看得见字、明显点不动」的一档，再低就认不出按钮上写的是「撤销」还是「重做」。
    public static let disabledActionTextAlpha: CGFloat = 0.35
    /// 动作按钮置灰时的底色折扣（可用态为 1，不可用只留四成）
    public static let disabledActionFillScale: CGFloat = 0.4

    /// 动作按钮文字 alpha：可用取常态档，不可用取置灰档
    public static func actionTextAlpha(_ normal: CGFloat, isEnabled: Bool) -> CGFloat {
        isEnabled ? normal : min(normal, disabledActionTextAlpha)
    }

    /// 动作按钮底色 alpha：不可用时整体降一档透明度，与可用的按钮在余光里也分得开
    public static func actionFillAlpha(_ normal: CGFloat, isEnabled: Bool) -> CGFloat {
        isEnabled ? normal : normal * disabledActionFillScale
    }

    // MARK: - 当前色圆点

    /// 当前色圆点是否带选中环
    ///
    /// 一级工具条只有一枚「当前色」，恒带白环才能一眼看出「这是现在的颜色、点它能换」；
    /// 二级面板里的色点是一组可选项，只有真正被选中的那一枚才带环。
    public static func colorDotRingVisible(isCurrentColor: Bool) -> Bool { isCurrentColor }

    // MARK: - 两级选中语言

    /// 选中语言：一级工具条整格填充，二级面板改用描边（两层选择不撞脸）
    public enum SnipBarSelectionStyle: Equatable, Sendable {
        /// 整格白底填充（一级工具条）
        case fill
        /// 浅底不变 + 强调色描边（二级面板）
        case stroke
    }

    /// 该层用哪套选中语言：面板 `.stroke`、一级工具条 `.fill`
    public static func selectionStyle(forPanel: Bool) -> SnipBarSelectionStyle {
        forPanel ? .stroke : .fill
    }

    /// 面板选中时的浅底 alpha（描边档：底只做同格调，不再靠明度分档）
    public static let panelSelectedFillAlpha: CGFloat = 0.10
    /// 面板选中描边宽度（pt）
    public static let selectionStrokeWidth: CGFloat = 1.5
}
