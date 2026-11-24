import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板窗口位置钉住

/// 把面板窗口钉在「展开那一刻」的锚点上：**横向以状态项中心居中，纵向顶边贴展开时的顶边**
///
/// 为什么横向是「居中」而不是「右对齐」：系统给 popover 画的顶端小三角恒在窗口水平中心，
/// 挪不动也改不了。右对齐状态项右边缘时三角会偏左（实测状态项中心 1038 / 窗口中心 956，
/// 偏 82pt，正指在「↓36K」那个字上），只有让窗口中心落在状态项中心，三角才真的指向点击的那个图标。
///
/// 为什么不是每次按当前值算：
/// - 横向：状态项宽度每秒随网速文字变化（实测 96…112pt），AppKit 每拍仍会按锚点重排
///   已展开的 popover，跟着最新值走等于永远追着跑；
/// - 纵向：popover 在内容尺寸变化时保持**底边**不动，顶边随高度跑。实测切 tab（内容高 350 / 506 /
///   537 / 546）时，屏幕坐标里的顶边在 28 / 33 / 42 / 73 / 229 之间跳、底边却恒为 579 ——
///   用户看到的就是「详情页位置时刻在变」。
///
/// 三条口径一起才成立：
/// 1. **横向从第一帧就钉**：popover 自己按「锚点中心」摆窗口，落点会跟着状态项宽度抖动。
///    原先横向纠正也被「出场动画结束」这道闸门挡着，于是前 240ms 用户看到的是 popover 自己摆的位置、
///    随后「啪」地跳一下 —— 逐帧轨迹里 14 帧停在旧 x 之后才变。
///    横向不需要等动画：锚点中心在 show 时就已冻结，动画期间 popover 也不改位置，
///    所以 attach 里立刻钉一次，之后由 didMove / didResize 保持纠正；
/// 2. **纵向顶边在出场动画结束后才锁**：动画期间窗口位置与尺寸都在变，实测按动画帧取到的顶边
///    比稳定值低 50pt，面板会被钉到屏幕中下部；所以纵向基准在动画结束后从真实 frame 锁一次；
/// 3. **只改原点、不改尺寸**：纠正走 setFrameOrigin，尺寸归 popover 自己管 ——
///    用 setFrame 在出场动画中途改框会把动画的中间态尺寸冻住（实测宽度 346 → 312）。
///
/// 触发时机：attach 时立刻钉一次横向；didMove / didResize 观察者在 armed 后**同步**纠正
/// （排队到下一轮会漏出一帧中间态，实测切页 857ms 时漏出 x=954），同时仍排一次补钉兜底。
@MainActor
enum PanelWindowPin {

    /// 本次展开记下的状态项中心 x（屏幕坐标）；nil = 没展开 / 已摘除
    private static var targetCenterX: CGFloat?
    /// 本次展开记下的目标顶边（屏幕坐标，bottom-left 原点）；nil = 没展开 / 已摘除
    private static var targetTopEdge: CGFloat?
    private static weak var panelWindow: NSWindow?
    private static var movers: [NSObjectProtocol] = []
    /// 合并用：已排队的下一轮补钉（多次触发只跑一次）
    private static var pendingPin: DispatchWorkItem?
    /// 出场动画结束前不改**纵向**：动画期间 popover 自己也在改 frame，插进去会和它抢。
    /// 横向不受这道闸门约束（锚点 show 时就冻结、动画不改位置），见类型注释第 1 条。
    private static var isArmed = false

    /// 面板显示后调用一次：记下锚点、立刻钉横向、挂上「被挪走 / 尺寸变了就按回来」的观察者
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
        targetCenterX = anchorRect.midX
        // 顶边不在这一刻取：show 之后、出场动画结束之前窗口还在动（实测按动画帧取到的顶边
        // 比稳定值低 50pt，面板会被钉到屏幕中下部）。等动画结束再锁一次真实顶边。
        panelWindow = window
        // 观察者不捕获 note（跨隔离域传 Notification 会被判数据竞争）：目标只有一个窗口
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { pinOnWindowEvent(logger: logger) }
                }
            movers.append(token)
        }
        // 横向立刻钉：用户看到的第一帧就应该是居中位置，而不是「先摆错再跳过去」。
        // 纵向此刻还没有基准（targetTopEdge 为 nil），这一步只动 x。
        pin(logger: logger)
        // 出场动画结束后才允许改纵向：动画期间 popover 自己在改 frame，插进去会和它抢。
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
        targetCenterX = nil
        targetTopEdge = nil
        isArmed = false
    }

    /// 面板内容高度重算后显式补钉一次
    ///
    /// popover.contentSize 赋值到窗口真正 resize 之间隔着一帧：等 didResize 落地会有可感知的
    /// 高度跳动，所以重算链路在改完尺寸后主动调这里，让顶边在同一帧内归位。
    static func repinAfterContentSizeChange(logger: LoggingService? = nil) {
        schedulePin(logger: logger)
    }

    /// 出场动画时长（秒）—— 动画结束后的补钉要排在它之后
    private static let postAnimationDelay: TimeInterval = 0.25

    /// 窗口自己被挪动 / 尺寸变化时：已 armed 就同步纠正（避免漏出一帧中间态），并再排一次补钉兜底
    ///
    /// 为什么同步：popover 改 contentSize 会把自己按锚点中心重摆，排队到下一轮 runloop 纠正的话，
    /// 中间态会实打实渲染一帧（实测切页 857ms 时漏出 x=954）。
    /// 为什么还要排一次：同一次 resize 里 popover 可能分两步改 frame，同步改完仍会被后一步覆盖。
    private static func pinOnWindowEvent(logger: LoggingService?) {
        if isArmed { pin(logger: logger) }
        schedulePin(logger: logger)
    }

    /// 把补钉合并到下一轮 runloop（动画帧里重复触发的只留一次）
    private static func schedulePin(logger: LoggingService?) {
        guard pendingPin == nil else { return }
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
    ///
    /// 横向随时可纠正（targetCenterX 在 show 时就冻结）；纵向只在 armed 之后，
    /// 因为要先拿到真实顶边（targetTopEdge）才算得出目标原点。
    private static func pin(logger: LoggingService?) {
        guard let window = panelWindow, let centerX = targetCenterX else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = window.frame
        // 口径（横向随时可算 / 纵向要先锁顶边）在 NetworkMonitorUI 的纯逻辑里，这里只落副作用
        let target = PanelAnchor.pinTarget(panelFrame: frame,
                                           statusItemCenterX: centerX,
                                           lockedTopEdge: isArmed ? targetTopEdge : nil,
                                           visible: visible)
        let targetY = target.y ?? frame.origin.y
        guard abs(frame.origin.x - target.x) > 0.5 || abs(frame.origin.y - targetY) > 0.5 else { return }
        let before = frame.origin
        window.setFrameOrigin(NSPoint(x: target.x, y: targetY))
        logger?.debug(String(format: "面板位置钉住：(%.1f, %.1f) → (%.1f, %.1f)，状态项中心 %.1f / 顶边 %@",
                             before.x, before.y, target.x, targetY, centerX,
                             targetTopEdge.map { String(format: "%.1f", $0) } ?? "未锁"))
    }
}
