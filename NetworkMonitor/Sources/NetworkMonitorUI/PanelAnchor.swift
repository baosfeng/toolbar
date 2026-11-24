import CoreGraphics

// MARK: - 面板锚点矩形（纯逻辑，可单测）

/// NSPopover 的锚点矩形 — 贴状态项**中心**的 1pt 窄矩形
///
/// 为什么是中心而不是右边缘：系统给 popover 画的顶端小三角（beak）**恒在窗口水平中心**，
/// 挪不动也改不了（实测用户截图里三角中心 362.4pt vs 面板中心 362.5pt，差 0.1pt）。
/// 所以「三角指向状态项」只能靠**让窗口中心落在状态项中心**来实现，
/// 右边缘对齐只会让三角指向状态项的左半截。
///
/// 实测（nmcli 连采同一进程）：状态项 947,4.5 183x24（中心 1038）时，右对齐口径把面板
/// 摆在 783，窗口中心 956，三角偏左 82pt，正指在「↓36K」那个字上。
///
/// 锚点宽度仍收成 1pt：
/// 1. 直接把 `button.bounds` 交给 popover → 锚点矩形随宽度变化，实测面板 x 跳 26pt；
/// 2. 把「宽 320pt、贴右边缘」的大矩形交进去 → 仍漂 10pt（越出按钮 bounds，
///    被 AppKit 按视图边界处理）。
///
/// 宽度 1pt 时锚点中心 = `bounds.midX`，与按钮宽度彻底无关；实测三种宽度
/// （120/175/220）下窗口中心与状态项中心的残差都在 0.5pt 内。
public enum PanelAnchor {

    /// 锚点矩形宽度（pt）—— 1pt：中心落在 `bounds.midX`，与按钮宽度解耦
    ///
    /// 不用面板宽度量级：越出按钮 bounds 的大矩形会被 AppKit 按视图边界处理，
    /// 中心重新带上按钮宽度分量，实测仍漂 10pt。
    public static let preferredWidth: CGFloat = 1

    /// 把状态项按钮的 bounds 换算成窄锚点矩形
    ///
    /// - Parameters:
    ///   - buttonBounds: 状态项按钮的 bounds（按钮自身坐标系）
    ///   - width: 锚点矩形宽度（<= 0 时回落到 1pt，不产生非法矩形）
    /// - Returns: 中心与按钮中心对齐的窄矩形（与入参同一坐标系）
    ///
    /// 高度与 y 沿用按钮：popover 以 `preferredEdge: .minY` 贴锚点矩形下边展开，
    /// 这里只锁横向口径，不改动纵向行为。
    public static func rect(for buttonBounds: CGRect,
                            width: CGFloat = preferredWidth) -> CGRect {
        let clampedWidth = width > 0 ? width : preferredWidth
        return CGRect(x: buttonBounds.midX - clampedWidth / 2,
                      y: buttonBounds.minY,
                      width: clampedWidth,
                      height: buttonBounds.height)
    }

    /// 面板横向钉住的目标原点 x —— **以状态项中心居中**
    ///
    /// NSPopover 自己的定位不完全可控：它会按「锚点中心居中 + 屏幕夹取」摆放窗口。
    /// 展开后由调用方按这里算出的 x 显式 setFrameOrigin，把横向位置钉死，
    /// 让「窗口中心 == 状态项中心」在任何一次展开里都成立。
    ///
    /// - Parameters:
    ///   - panelWidth: 面板窗口宽度（pt）
    ///   - statusItemCenterX: 状态项中心的屏幕坐标（同一坐标系）
    ///   - visibleMinX / visibleMaxX: 屏幕可视区左右边界（面板不得越出）
    /// - Returns: 目标原点 x；面板越界时先贴左边界、再夹到右边界
    public static func pinnedX(panelWidth: CGFloat,
                               statusItemCenterX: CGFloat,
                               visibleMinX: CGFloat,
                               visibleMaxX: CGFloat) -> CGFloat {
        guard panelWidth > 0 else { return visibleMinX }
        let centered = statusItemCenterX - panelWidth / 2
        let upperBound = max(visibleMinX, visibleMaxX - panelWidth)
        return min(max(centered, visibleMinX), upperBound)
    }

    /// 面板纵向钉住的目标原点 y —— **顶边**贴展开那一刻的顶边，高度变化只向下长
    ///
    /// 为什么钉顶边而不是让 AppKit 自己排：popover 在内容尺寸变化时保持**底边**不动，
    /// 顶边随高度上下跑。实测同一台机器切 tab（高度 350 / 506 / 537 / 546）时顶边在
    /// 28 / 33 / 42 / 73 / 229 之间跳，底边恒为 579 —— 用户看到的就是「详情页位置时刻在变」。
    /// 钉住顶边后，切到更矮的页（额度 350）面板仍贴在菜单栏下沿，而不是掉到屏幕中下部。
    ///
    /// 边界：顶边不越出可视区上沿；面板比可视区还高时回落可视区下沿（贴地优先于贴顶）。
    ///
    /// - Parameters:
    ///   - panelHeight: 面板窗口高度（pt）
    ///   - panelTopEdge: 展开那一刻记下的窗口顶边（屏幕坐标，bottom-left 原点）
    ///   - visibleMinY / visibleMaxY: 屏幕可视区上下边界（面板不得越出）
    /// - Returns: 目标原点 y（NSWindow.frame 用 bottom-left 坐标，origin.y 即底边）
    public static func pinnedOriginY(panelHeight: CGFloat,
                                     panelTopEdge: CGFloat,
                                     visibleMinY: CGFloat,
                                     visibleMaxY: CGFloat) -> CGFloat {
        guard panelHeight > 0 else { return visibleMinY }
        let topEdge = min(panelTopEdge, visibleMaxY)
        return max(topEdge - panelHeight, visibleMinY)
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

    // MARK: - 钉住目标（横向 / 纵向分开算）

    /// 一次纠正的目标原点 —— 横向与纵向各有自己的「能不能算」条件
    ///
    /// 为什么要分两个方向：popover 摆窗口时按「锚点中心」定位，而纵向在出场动画期间
    /// 窗口还在长，取不到稳定顶边。两者的可纠正时机不同，混在一个开关里就会出现
    /// 「横向也跟着等 240ms」——用户看到的是「先居中再跳」。
    public struct PinTarget: Equatable {
        /// 纠正后的原点 x
        public let x: CGFloat
        /// 纠正后的原点 y；nil = 纵向还没基准，本次不动 y
        public let y: CGFloat?
        public init(x: CGFloat, y: CGFloat?) {
            self.x = x
            self.y = y
        }
    }

    /// 算一次纠正目标 —— 横向随时可算（状态项中心 show 时就冻结），纵向只在拿到真实顶边后可算
    ///
    /// - Parameters:
    ///   - panelFrame: 面板窗口当前 frame
    ///   - statusItemCenterX: 展开那一刻记下的状态项中心（屏幕坐标）
    ///   - lockedTopEdge: 出场动画结束后锁下的顶边；nil = 还没锁
    ///   - visible: 屏幕可视区
    /// - Returns: 目标原点；纵向未锁时 y 为 nil（调用方保持当前 y 不动）
    public static func pinTarget(panelFrame: CGRect,
                                 statusItemCenterX: CGFloat,
                                 lockedTopEdge: CGFloat?,
                                 visible: CGRect) -> PinTarget {
        let x = pinnedX(panelWidth: panelFrame.width,
                        statusItemCenterX: statusItemCenterX,
                        visibleMinX: visible.minX,
                        visibleMaxX: visible.maxX)
        guard let top = lockedTopEdge else { return PinTarget(x: x, y: nil) }
        let y = pinnedOriginY(panelHeight: panelFrame.height,
                              panelTopEdge: top,
                              visibleMinY: visible.minY,
                              visibleMaxY: visible.maxY)
        return PinTarget(x: x, y: y)
    }
}
