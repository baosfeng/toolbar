#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 贴图窗鼠标手势自证（仅 DEBUG）

/// 用真实 CGEvent 打完整鼠标手势链，定位拖动断在哪一层、并守住其余手势不回归
///
/// 触发方式（必须在 .app 里跑，裸二进制会崩在 UserNotifications）：
/// - `NM_PIN_DRAG_PROBE=1`：跑完整手势矩阵 → 打印结论 → 退出；
/// - `NM_PIN_DRAG_PROBE=hold`：拖动前后各自抓一张整屏图 + 打一份 CGWindowList 里的窗口 bounds，
///   方便人工核对「窗口真的挪了」；
/// - `NM_PIN_DRAG_DELAY=<秒>`：贴图后等多久才开拖（默认 0.5）。App 被别的 App 抢走前台后
///   贴图窗不再是 key window，这条用来复现「非活跃态拖动」。
///
/// 全程走 `.cghidEventTap` 投递真实 HID 事件，不调 NSApp.sendEvent，
/// 因此「事件到没到视图 / 窗口有没有真的动」都是真机结论。
@MainActor
enum PinDragProbe {

    static let envKey = "NM_PIN_DRAG_PROBE"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    private static var isHolding: Bool {
        ProcessInfo.processInfo.environment[envKey] == "hold"
    }

    /// 内容视图收到的左键按下次数（只在探针开启时累加）
    private(set) static var mouseDownCount = 0
    /// 右键菜单装配次数（PinWindow.rightMouseDown 每次弹菜单 +1）
    private(set) static var contextMenuCount = 0

    static func recordMouseDown() {
        guard isRequested else { return }
        mouseDownCount += 1
    }

    /// 拖动会话起点（内容视图自己算位移时调用）
    static func noteDragStart(origin: CGPoint, mouse: CGPoint) {
        guard isRequested else { return }
        print("🔎 拖动会话开始：窗口原点=\(origin)，鼠标=\(mouse)")
    }

    /// 拖动过程中的每一帧（只打印首帧与末帧，避免刷屏）
    static func recordDragFrame(_ frame: CGRect) {
        guard isRequested else { return }
        dragFrameCount += 1
        if dragFrameCount == 1 || dragFrameCount % 20 == 0 {
            print("🔎 拖动第 \(dragFrameCount) 帧：frame=\(frame.origin) \(frame.size)")
        }
    }

    private(set) static var dragFrameCount = 0

    static func recordContextMenu() {
        guard isRequested else { return }
        contextMenuCount += 1
    }

    // MARK: - 探针主流程

    /// 环境变量就绪时启动探针（入口在 AppDelegate 的 DEBUG 段）
    static func runIfRequested(pin: PinWindowController) {
        guard isRequested else { return }
        run(pin: pin, logger: AppContext.shared.logger)
    }

    static func run(pin: PinWindowController, logger: LoggingService) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            let size = CGSize(width: 240, height: 180)
            let cgRect = CGRect(x: 360, y: 320, width: size.width, height: size.height)
            let window = pin.pin(image: sampleImage(size), cgRect: cgRect)
            // hold 模式：先停 3 秒并标 pinned，供外部工具拍「拖动前」这一张
            // NM_PIN_DRAG_DELAY 用来扫「贴图后等多久再拖」这个变量：
            // 实测等得越久越拖不动（App 失去活跃状态），这里把它做成可配参数取证
            let delay = Double(ProcessInfo.processInfo.environment["NM_PIN_DRAG_DELAY"] ?? "") ?? 0.5
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            reportHitTest(window)
            await dragPhase(window)
            await scrollPhase(window)
            await middleClickPhase(window)
            await rightClickPhase(window, pin: pin)
            let survived = await doubleClickPhase(window, pin: pin)

            print("━━━━━━━━ 贴图窗手势矩阵结论 ━━━━━━━━")
            print("🔎 mouseDown 次数=\(mouseDownCount) 右键菜单装配次数=\(contextMenuCount)")
            print("🔎 双击关闭后窗口是否还在=\(survived ? "在（未关闭）" : "已关闭")，剩余贴图 \(pin.count) 张")
            logger.info("贴图手势探针完成：mouseDown \(mouseDownCount)，菜单 \(contextMenuCount)，剩余 \(pin.count) 张")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            exit(0)
        }
    }

    // MARK: - 各手势阶段

    private static func reportHitTest(_ window: PinWindow) {
        guard let content = window.contentView else { return }
        let frame = window.frame
        // 窗口内坐标（原点在窗口左下角）才是 convert(from: nil) 的口径
        let pointInWindow = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let pointInContent = content.convert(pointInWindow, from: nil)
        let hit = content.hitTest(pointInContent).map { "\(type(of: $0))" } ?? "nil"
        print("🔎 [1/5] contentView.hitTest(窗口中心) → \(hit)")
    }

    /// 阶段 1：按住左键拖 140×90，窗口 frame 必须跟着走
    private static func dragPhase(_ window: PinWindow) async {
        let before = window.frame
        let start = CGPoint(x: before.midX, y: before.midY)
        print("🔎 [2/5] 拖动前 frame=\(none(before))，isKeyWindow=\(window.isKeyWindow)")
        if isHolding {
            // 拖动前的自证：从 CGWindowList 现读贴图窗（layer=1000）的屏幕 bounds，并抓一张整屏图。
            // 都在进程内完成，不引入会抢前台的外部截图工具。
            print("🔎 CGWindowList 拖动前：\(self.screenBoundsDescription())")
            captureScreen(to: beforePath)
            markPhase("pinned")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        // 事件投递放后台线程：主线程要空出来处理窗口事件
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                postDrag(from: start, delta: CGSize(width: 140, height: -90))
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        let after = window.frame
        let dx = after.origin.x - before.origin.x
        let dy = after.origin.y - before.origin.y
        markPhase("after")
        print("🔎 [2/5] 拖动后 frame=\(none(after)) 位移 Δx=\(dx) Δy=\(dy) "
              + "mouseDown 次数=\(mouseDownCount) 拖动帧=\(dragFrameCount)")
        if isHolding {
            print("🔎 CGWindowList 拖动后：\(self.screenBoundsDescription())")
            captureScreen(to: afterPath)
        }
        print(dx != 0 || dy != 0 ? "✅ 拖动生效" : "❌ 拖动未生效（窗口没动）")
        if isHolding {
            print("🔎 hold 模式：窗口停在 \(none(after))，6 秒后退出")
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            exit(0)
        }
    }

    /// 阶段 2：滚轮必须仍在缩放（贴图窗 scrollWheel 的口径是每格 2%）
    private static func scrollPhase(_ window: PinWindow) async {
        let beforeScale = window.currentScale
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let point = cgPoint(center)
                for _ in 0..<3 {
                    CGEvent(scrollWheelEvent2Source: nil, units: .line,
                            wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0)?
                        .post(tap: .cghidEventTap)
                    sleepMilliseconds(60)
                }
                _ = point
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let afterScale = window.currentScale
        print("🔎 [3/5] 滚轮缩放 \(beforeScale) → \(afterScale)"
              + (afterScale > beforeScale ? " ✅" : " ❌ 滚轮没生效"))
    }

    /// 阶段 3：中键单击必须重置回 100% 大小与 100% 不透明
    private static func middleClickPhase(_ window: PinWindow) async {
        window.setScale(2)
        window.adjustAlpha(by: -0.5)
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let point = cgPoint(center)
                post(type: .otherMouseDown, at: point, button: .center)
                sleepMilliseconds(80)
                post(type: .otherMouseUp, at: point, button: .center)
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let reset = abs(window.currentScale - 1) < 0.0001 && abs(window.alphaValue - 1) < 0.0001
        print("🔎 [4/5] 中键重置后 scale=\(window.currentScale) alpha=\(window.alphaValue) "
              + (reset ? "✅" : "❌ 中键没生效"))
    }

    /// 阶段 4：右键必须弹菜单（而不是被当成拖动把手）
    private static func rightClickPhase(_ window: PinWindow, pin: PinWindowController) async {
        let before = window.frame
        let center = CGPoint(x: before.midX, y: before.midY)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let point = cgPoint(center)
                post(type: .rightMouseDown, at: point, button: .right)
                sleepMilliseconds(120)
                post(type: .rightMouseUp, at: point, button: .right)
                // 菜单开着会进入模态跟踪循环，850ms 后按 Esc 收掉，主线程才回得来
                sleepMilliseconds(850)
                let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)
                escape?.post(tap: .cghidEventTap)
                sleepMilliseconds(80)
                let escapeUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)
                escapeUp?.post(tap: .cghidEventTap)
                sleepMilliseconds(400)
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let after = window.frame
        let moved = after.origin != before.origin
        print("🔎 [5/5] 右键后菜单装配次数=\(contextMenuCount)，窗口位移=\(moved ? "有（错！右键被当成拖动）" : "无（正确）")"
              + "，贴图数=\(pin.count)")
    }

    /// 阶段 5：左键双击必须关闭贴图
    private static func doubleClickPhase(_ window: PinWindow, pin: PinWindowController) async -> Bool {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let point = cgPoint(center)
                for clickState in 1...2 {
                    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                       mouseCursorPosition: point, mouseButton: .left)
                    down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                    down?.post(tap: .cghidEventTap)
                    sleepMilliseconds(40)
                    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                     mouseCursorPosition: point, mouseButton: .left)
                    up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                    up?.post(tap: .cghidEventTap)
                    sleepMilliseconds(60)
                }
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return window.isVisible && pin.count > 0
    }

    // MARK: - 事件投递

    /// 一条完整的按下 → 分步拖动 → 松开
    private static func postDrag(from start: CGPoint, delta: CGSize) {
        let startCG = cgPoint(start)
        moveMouse(to: startCG)
        sleepMilliseconds(120)
        post(type: .leftMouseDown, at: startCG, button: .left)
        sleepMilliseconds(150)
        let steps = 10
        for step in 1...steps {
            let ratio = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: startCG.x + delta.width * ratio,
                                y: startCG.y + delta.height * ratio)
            post(type: .leftMouseDragged, at: point, button: .left)
            sleepMilliseconds(40)
        }
        sleepMilliseconds(120)
        post(type: .leftMouseUp,
             at: CGPoint(x: startCG.x + delta.width, y: startCG.y + delta.height),
             button: .left)
    }

    private static func moveMouse(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func post(type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    private static func sleepMilliseconds(_ value: UInt32) {
        usleep(value * 1000)
    }

    // MARK: - 与外部采样脚本的阶段同步

    /// 阶段标记文件：内容为 pinned / after，外部脚本据此在正确时机补采 nmcli windows
    static let phaseFilePath = "/tmp/pin-drag-phase.txt"

    private static func markPhase(_ phase: String) {
        guard isHolding else { return }
        try? phase.write(toFile: phaseFilePath, atomically: true, encoding: .utf8)
    }

    /// AppKit（左下原点）→ CG 全局（左上原点）
    private static func cgPoint(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    private static func none(_ rect: CGRect) -> String {
        "(\(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height))"
    }

    private static func sampleImage(_ size: CGSize) -> CGImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.setFill()
        NSRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40).fill()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
#endif