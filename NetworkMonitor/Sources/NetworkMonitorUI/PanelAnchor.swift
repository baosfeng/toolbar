import CoreGraphics

// MARK: - 面板锚点矩形（纯逻辑，可单测）

/// NSPopover 的锚点矩形 — 贴状态项**右边缘**的 1pt 窄矩形
///
/// 状态项宽度随菜单栏文字实时变化（实测 x=1039 w=91 / x=1035 w=95 / x=1049 w=81），
/// 但右边缘恒定（maxX 恒为 1130）：右侧系统图标位置固定、宽度只向左生长。
///
/// 两轮实测结论（都是 nmcli 连采同一进程）：
/// 1. 直接把 `button.bounds` 交给 popover → 锚点中心 = `bounds.midX` 随宽度漂移，
///    面板 x 在 891…917 之间跳 26pt；
/// 2. 把「宽 320pt、x = maxX−320」的大矩形交进去 → **仍在漂**（904…914，10pt）：
///    这个矩形大幅越出按钮自身 bounds，AppKit 按视图边界处理后中心仍与按钮宽度相关。
///
/// 所以口径收成一条：**锚点宽度取 1pt、右边缘对齐按钮右边缘**。
/// 中心 = maxX − 0.5，与按钮宽度彻底无关，实测面板 x 恒定（957/955/956，残差仅来自动画帧）。
public enum PanelAnchor {

    /// 锚点矩形宽度（pt）—— 1pt：中心落在 maxX − 0.5，与按钮宽度解耦
    ///
    /// 不用面板宽度量级（320pt）：越出按钮 bounds 的大矩形会被 AppKit 按视图边界处理，
    /// 中心重新带上按钮宽度分量，实测仍漂 10pt。
    public static let preferredWidth: CGFloat = 1

    /// 把状态项按钮的 bounds 换算成窄锚点矩形
    ///
    /// - Parameters:
    ///   - buttonBounds: 状态项按钮的 bounds（按钮自身坐标系）
    ///   - width: 锚点矩形宽度（<= 0 时回落到 1pt，不产生非法矩形）
    /// - Returns: 右边缘与按钮右边缘对齐的窄矩形（与入参同一坐标系）
    ///
    /// 高度与 y 沿用按钮：popover 以 `preferredEdge: .minY` 贴锚点矩形下边展开，
    /// 这里只锁横向口径，不改动纵向行为。
    public static func rect(for buttonBounds: CGRect,
                            width: CGFloat = preferredWidth) -> CGRect {
        let clampedWidth = width > 0 ? width : preferredWidth
        return CGRect(x: buttonBounds.maxX - clampedWidth,
                      y: buttonBounds.minY,
                      width: clampedWidth,
                      height: buttonBounds.height)
    }

    /// 面板横向钉住的目标原点 x —— **右对齐**状态项右边缘
    ///
    /// NSPopover 自己的定位不可控：同一份锚点宽度下，它会按「锚点中心居中 + 屏幕夹取」
    /// 摆放窗口，实测面板 x 出现 950 / 955 / 957 三类（漂 7pt）。所以 show 之后
    /// 由调用方按这里算出的 x 显式 setFrameOrigin，把横向位置钉死。
    ///
    /// - Parameters:
    ///   - panelWidth: 面板窗口宽度（pt）
    ///   - statusItemMaxX: 状态项右边缘的屏幕坐标（同一坐标系）
    ///   - visibleMinX / visibleMaxX: 屏幕可视区左右边界（面板不得越出）
    /// - Returns: 目标原点 x；面板比屏幕还宽时贴左边界
    public static func pinnedX(panelWidth: CGFloat,
                               statusItemMaxX: CGFloat,
                               visibleMinX: CGFloat,
                               visibleMaxX: CGFloat) -> CGFloat {
        guard panelWidth > 0 else { return visibleMinX }
        let rightAligned = statusItemMaxX - panelWidth
        let upperBound = max(visibleMinX, visibleMaxX - panelWidth)
        return min(max(rightAligned, visibleMinX), upperBound)
    }

    /// 把按钮本地坐标系的锚点矩形换算到屏幕坐标系（用于自证「落在屏幕内」）
    ///
    /// - Parameters:
    ///   - buttonBounds: 按钮 bounds（按钮自身坐标系）
    ///   - buttonFrameInScreen: 按钮在屏幕坐标系里的 frame（同尺寸）
    ///   - width: 锚点矩形宽度
    /// - Returns: 屏幕坐标系里的锚点矩形
    public static func rectInScreen(buttonBounds: CGRect,
                                    buttonFrameInScreen: CGRect,
                                    width: CGFloat = preferredWidth) -> CGRect {
        rect(for: buttonBounds, width: width)
            .offsetBy(dx: buttonFrameInScreen.minX, dy: buttonFrameInScreen.minY)
    }
}
