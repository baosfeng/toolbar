import AppKit
import NetworkMonitorCore

// MARK: - 覆盖层窗口

/// 每屏一个的截图覆盖层窗口 — 无边框、置顶到 screenSaver 层级、可跨 Space
///
/// 用 NSPanel + .nonactivatingPanel 而不是普通 NSWindow：菜单栏 App 是
/// LSUIElement（accessory），NSApp.activate(ignoringOtherApps:) 从 macOS 14 起
/// 被标记废弃且实测无效（active 仍为 false、isKeyWindow 也拿不到），
/// 于是覆盖层画得出来却不吃键盘（Esc / 回车 / ⌘S 全无反应）。
/// nonactivatingPanel 让窗口自己成为 key window 而不要求 App 变成前台，
/// 实测 makeKeyAndOrderFront 后 isKey=true 且键盘事件照常投递。
@MainActor
final class SnipOverlayWindow: NSPanel {

    private(set) var overlayView: SnipOverlayView

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(display: SnipDisplay,
         screenshot: CGImage,
         windowInfos: [SnipWindowInfo],
         lastSelection: CGRect?,
         history: [CGRect],
         primaryHeight: CGFloat,
         initialStyle: SnipAnnotationStyle,
         delegate: SnipOverlayViewDelegate) {
        let frame = SelectionGeometry.appKitRect(fromCG: display.frame, primaryHeight: primaryHeight)
        let view = SnipOverlayView(frame: NSRect(origin: .zero, size: frame.size),
                                   screenshot: screenshot,
                                   windowInfos: windowInfos,
                                   displayOrigin: display.frame.origin,
                                   lastSelection: lastSelection,
                                   history: history,
                                   initialStyle: initialStyle)
        overlayView = view
        // .nonactivatingPanel：窗口可成为 key 而不要求 App 变成前台（见类型注释）
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = view
        view.delegate = delegate
    }

    /// 淡入任务：首帧超时兜底用（见 present()）
    private var fadeInTask: Task<Void, Never>?

    /// 展示并接管键盘
    ///
    /// 菜单栏 App（LSUIElement + 自签名）不是天然可激活的前台应用：
    /// 第一次调用 activate 常常只是「排队」，窗口已经 isKeyWindow 却仍收不到键盘，
    /// 于是会出现「第一次按 Esc 没反应、第二次起才正常」。
    /// 这里改成有限重试：每 80ms 试一次 activate 并核对 frontmost，最多 12 次（约 1 秒），
    /// 拿到前台就停。拿不到也不会卡住，仍由本地键盘兜底监视器接住按键。
    ///
    /// 另外「按完热键屏幕闪一下」的成因是：覆盖层上屏的第一帧是空白（back store 未建好），
    /// 直接以不透明上屏会让用户先看到一块纯色再看到截图内容。这里改成以 alpha 0 上屏
    /// （照样拿得到 key window 与键盘），首帧真正画好后再淡入 80ms。

    @discardableResult
    func present() -> Bool {
        enterInteractiveMode()
        // 先透明上屏：既拿到 key window 与键盘，又不让用户看到空白帧
        alphaValue = 0
        overlayView.onFirstFrameRendered = { [weak self] in
            self?.fadeInAfterFirstFrame()
        }
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(overlayView)
        overlayView.needsDisplay = true
        scheduleActivationRetry()
        // 兜底：首帧真的画不出来（拿不到绘图上下文且重试耗尽）也要让窗口可见，
        // 否则用户面对的是一片看不见的覆盖层，比闪一下更糟
        fadeInTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.alphaValue < 1 else { return }
            AppContext.shared.logger.warning("覆盖层首帧超时，直接显示")
            self.alphaValue = 1
        }
        return isKeyWindow
    }

    /// 首帧画完后淡入（80ms）：用户只看到「原画面 → 截图画面」的直接交接
    private func fadeInAfterFirstFrame() {
        fadeInTask?.cancel()
        fadeInTask = nil
        guard alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// 截图期间临时变成「可被激活的应用」，截图结束再由调用方切回 .accessory
    ///
    /// LSUIElement 的菜单栏 App 不是可被激活的应用：`activate` 返回成功、
    /// isActive 也变 true，但系统 frontmost 仍是原 App，键盘事件继续投给原前台，
    /// 于是 Esc / 回车时灵时不灵（实测 5 轮里 1~2 轮失效）。
    /// 临时切到 .regular 后系统才真正把前台交过来，截图结束立刻切回，
    /// 不会在 Dock 里留下图标——这正是「打开输入框前也要能打字」的通行做法。
    func enterInteractiveMode() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 有限次抢占前台（每次拿到就停，失败也最多等约 1 秒）
    private func scheduleActivationRetry(attempt: Int = 0) {
        guard attempt < 12 else {
            AppContext.shared.logger.warning("覆盖层未能抢占前台，已改由键盘兜底接键")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.08)) { [weak self] in
            guard let self else { return }
            let ours = NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
            if ours {
                self.makeKey()
                self.makeFirstResponder(self.overlayView)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKey()
            self.scheduleActivationRetry(attempt: attempt + 1)
        }
    }
}
