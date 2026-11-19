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
         toolbarConfiguration: SnipToolBarConfiguration,
         delegate: SnipOverlayViewDelegate) {
        let frame = SelectionGeometry.appKitRect(fromCG: display.frame, primaryHeight: primaryHeight)
        let view = SnipOverlayView(frame: NSRect(origin: .zero, size: frame.size),
                                   screenshot: screenshot,
                                   windowInfos: windowInfos,
                                   displayOrigin: display.frame.origin,
                                   lastSelection: lastSelection,
                                   history: history,
                                   initialStyle: initialStyle,
                                   toolbarConfiguration: toolbarConfiguration)
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
        claimFirstResponderIfNeeded()
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

    /// 进入交互态：只激活 + 让自己成为 key window，**不切激活策略**
    ///
    /// 早期这里切 .regular，理由是「.accessory 下系统不肯把前台交过来」。
    /// 代价是每次截图 Dock 都闪一个图标（用户口径：「每次截图 dock 栏都会出现我们的软件」）。
    /// 实测（macOS 27）：`.nonactivatingPanel` + `canBecomeKey` 的窗口
    /// makeKey 之后照样收到 keyDown（Esc / 方向键都投递到视图），
    /// 与 App 是否 `.regular` 无关；不切策略就没有 Dock 图标，因此这里只留 activate。
    func enterInteractiveMode() {
        SnipForegroundPolicy.claimForeground()
    }

    /// 把键盘焦点给覆盖层，但**不抢正在编辑的输入框**
    ///
    /// `scheduleActivationRetry` 会在覆盖层上屏后每 80ms 重试一次、最多约 1 秒，
    /// 每次都无条件 `makeFirstResponder(overlayView)`——用户在这 1 秒内点「文字」并点画布，
    /// 刚设好的输入框焦点会被紧随其后的重试抢回覆盖层，表现就是「偶发打不进字」。
    /// 输入框在编辑时这里只保留 key window，焦点原样留在输入框里。
    private func claimFirstResponderIfNeeded() {
        guard !overlayView.hasActiveTextInput else { return }
        makeFirstResponder(overlayView)
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
                self.claimFirstResponderIfNeeded()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKey()
            self.scheduleActivationRetry(attempt: attempt + 1)
        }
    }
}
