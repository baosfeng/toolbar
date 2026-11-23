import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板窗口位置钉住

/// 把面板窗口钉在「展开那一刻」的锚点上：**横向右对齐状态项右边缘，纵向顶边贴状态项下沿**
///
/// 为什么不是每次按当前值算：
/// - 横向：状态项宽度每秒随网速文字变化（实测 96…112pt），右边缘虽然恒定，但 AppKit 每拍
///   仍会按锚点重排已展开的 popover（实测面板 x 在 757…777 之间来回），跟着最新值走等于永远追着跑；
/// - 纵向：popover 在内容尺寸变化时保持**底边**不动，顶边随高度跑。实测切 tab（内容高 350 / 506 /
///   537 / 546）时，屏幕坐标里的顶边在 28 / 33 / 42 / 73 / 229 之间跳、底边却恒为 579 ——
///   用户看到的就是「详情页位置时刻在变」。
///
/// 两条口径一起才成立：
/// 1. **顶边在出场动画结束后才锁**：横向锚点（状态项右边缘）show 之后立刻可用，纵向锚点不行——
///    动画期间窗口位置与尺寸都在变，实测按动画帧取到的顶边比稳定值低 50pt，面板会被钉到
///    屏幕中下部；所以纵向基准在动画结束后从窗口真实 frame 锁一次，之后整次展开不再变；
/// 2. **只改原点、不改尺寸**：纠正走 `setFrameOrigin`，尺寸归 popover 自己管——
///    用 `setFrame` 在出场动画中途改框会把动画的中间态尺寸冻住（实测宽度 346 → 312）。
///
/// 触发时机：`didMove` / `didResize` 观察者 + 内容高度重算后的显式补钉；每次都合并到下一轮
/// runloop 执行，避免在动画帧里同步改窗口。结果是整次展开期间面板右上角恒定，高度变化只向下长。
@MainActor
enum PanelWindowPin {

    /// 本次展开记下的目标右边缘（屏幕坐标）；nil = 没展开 / 已摘除
    private static var targetRightEdge: CGFloat?
    /// 本次展开记下的目标顶边（屏幕坐标，bottom-left 原点）；nil = 没展开 / 已摘除
    private static var targetTopEdge: CGFloat?
    private static weak var panelWindow: NSWindow?
    private static var movers: [NSObjectProtocol] = []
    /// 合并用：已排队的下一轮补钉（多次触发只跑一次）
    private static var pendingPin: DispatchWorkItem?
    /// 出场动画结束前不碰窗口：动画期间 popover 自己也在改 frame，插进去会和它抢
    private static var isArmed = false

    /// 面板显示后调用一次：记下锚点、挂上「被挪走 / 尺寸变了就按回来」的观察者，并补钉到位
    ///
    /// - Parameters:
    ///   - popover: 已 show 过、能拿到窗口的 popover
    ///   - anchorView: 状态项按钮（锚点从它的屏幕矩形算，与出场动画无关）
    ///   - logger: 记录纠正结果（便于取证复跑；传 nil 不打日志）
    static func attach(to popover: NSPopover,
                       anchorView: NSView?,
                       logger: LoggingService? = nil) {
        detach()
        guard let window = popover.contentViewController?.view.window,
              let anchor = anchorView,
              let anchorWindow = anchor.window else { return }
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        targetRightEdge = anchorRect.maxX
        // 顶边不在这一刻取：show 之后、出场动画结束之前窗口还在动（实测按动画帧取到的顶边
        // 比稳定值低 50pt，面板会被钉到屏幕中下部）。等动画结束再锁一次真实顶边。
        panelWindow = window
        // 观察者不捕获 note（跨隔离域传 Notification 会被判数据竞争）：目标只有一个窗口
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { schedulePin(logger: logger) }
                }
            movers.append(token)
        }
        // 出场动画结束后才允许改窗口：动画期间 popover 自己在改 frame，插进去会和它抢。
        // 也是在这一刻才锁顶边——此时窗口尺寸与位置都是最终值。
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.postAnimationDelay) {
            MainActor.assumeIsolated {
                targetTopEdge = panelWindow?.frame.maxY
                isArmed = true
                pin(logger: logger)
            }
        }
    }

    /// 收起后摘掉观察者与目标（下次展开重新取锚点）
    static func detach() {
        for token in movers { NotificationCenter.default.removeObserver(token) }
        movers.removeAll()
        pendingPin?.cancel()
        pendingPin = nil
        panelWindow = nil
        targetRightEdge = nil
        targetTopEdge = nil
        isArmed = false
    }

    /// 面板内容高度重算后显式补钉一次
    ///
    /// `popover.contentSize` 赋值到窗口真正 resize 之间隔着一帧：等 didResize 落地会有可感知的
    /// 高度跳动，所以重算链路在改完尺寸后主动调这里，让顶边在同一帧内归位。
    static func repinAfterContentSizeChange(logger: LoggingService? = nil) {
        schedulePin(logger: logger)
    }

    /// 出场动画时长（秒）—— 动画结束后的补钉要排在它之后
    private static let postAnimationDelay: TimeInterval = 0.25

    /// 把补钉合并到下一轮 runloop（动画帧里触发的 didMove / didResize 只留一次）
    private static func schedulePin(logger: LoggingService?) {
        guard isArmed, pendingPin == nil else { return }
        let item = DispatchWorkItem { [logger] in
            MainActor.assumeIsolated {
                pendingPin = nil
                pin(logger: logger)
            }
        }
        pendingPin = item
        DispatchQueue.main.async(execute: item)
    }

    /// 纠正位置：**只改原点**，尺寸交给 popover（改尺寸会让出场动画的中间态被冻住）
    private static func pin(logger: LoggingService?) {
        guard let window = panelWindow,
              let rightEdge = targetRightEdge,
              let topEdge = targetTopEdge else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = window.frame
        let targetX = PanelAnchor.pinnedX(panelWidth: frame.width,
                                          statusItemMaxX: rightEdge,
                                          visibleMinX: visible.minX,
                                          visibleMaxX: visible.maxX)
        let targetY = PanelAnchor.pinnedOriginY(panelHeight: frame.height,
                                                panelTopEdge: topEdge,
                                                visibleMinY: visible.minY,
                                                visibleMaxY: visible.maxY)
        guard abs(frame.origin.x - targetX) > 0.5 || abs(frame.origin.y - targetY) > 0.5 else { return }
        let before = frame.origin
        window.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        logger?.debug(String(format: "面板位置钉住：(%.1f, %.1f) → (%.1f, %.1f)，锚点右边缘 %.1f / 顶边 %.1f",
                             before.x, before.y, targetX, targetY, rightEdge, topEdge))
    }
}
