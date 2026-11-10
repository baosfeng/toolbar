import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 截图编排

/// 截图与贴图的总编排 — 热键 → 捕获 → 覆盖层选区 → 复制 / 贴到屏幕
///
/// 覆盖层窗口每屏一个；确认或取消后全部销毁。M1 阶段只做单屏选区，
/// 跨屏选区在 M2 处理。
@MainActor
final class SnipController: SnipOverlayViewDelegate {

    /// 放宽为 internal：热键扩展文件要用
    let captureService: any SnipCaptureServicing
    /// 放宽为 internal：导出扩展文件要贴图
    let pinWindows: PinWindowController
    /// 放宽为 internal：热键扩展文件要用
    let hotKeys: HotKeyRegistry
    /// 放宽为 internal：导出扩展要解析快速保存目录
    let storage: KeyValueStorage
    /// 截图快捷键偏好（lazy 是为了和 storage 同步初始化）
    let hotKeyPreferences: SnipHotKeyPreferences
    /// 已注册热键 id，按动作映射（用于重新录制时注销旧注册）
    var registeredHotKeyIDs: [SnipHotKeyAction: UInt32] = [:]
    /// 放宽为 internal：导出扩展文件要写日志
    let logger: LoggingService

    /// 上次成功截图的选区（全局 CG 坐标）在存储里的键
    /// 放宽为 internal：热键扩展文件要用
    static let lastSelectionKey = "snip.lastSelection"
    /// 最近若干次选区（逗号 / 句号循环）在存储里的键
    /// 放宽为 internal：热键扩展文件要用
    static let historyKey = "snip.selectionHistory"

    /// 放宽为 internal：热键扩展文件要清理覆盖层
    var overlays: [SnipOverlayWindow] = []
    /// 放宽为 internal：热键扩展文件要读捕获结果
    var captures: [SnipCapturedImage] = []
    /// 当前截图是否包含鼠标指针（由反引号键切换）
    private var cursorIncluded = false
    /// 截图是否正在准备（抓屏 / 抢前台阶段）；用于挡住热键重入
    private var isStarting = false
    /// 覆盖层键盘兜底监视器（覆盖层存在期间安装）
    /// 放宽为 internal：键盘扩展文件要读写
    var keyboardFallback: Any?
    /// 系统层按键桥（CGEventTap 回调 → 主线程）
    /// 放宽为 internal：键盘扩展文件要读写
    var keyboardBridge: SnipKeyboardTapBridge?
    /// 系统层按键 tap 与其 run loop source
    /// 放宽为 internal：键盘扩展文件要读写
    var eventTap: CFMachPort?
    var eventTapSource: CFRunLoopSource?
    /// 系统层 tap 缺失的提示是否已记录（避免每次截图刷一条）
    var keyboardTapWarningShown = false

    /// 打开设置窗（⌥⇧,） — 由组合根注入
    var onOpenSettings: (() -> Void)?
    /// 设置窗热键
    /// 放宽为 internal：热键扩展文件要用
    static let settingsCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_Comma),
                                                   modifiers: UInt32(optionKey | shiftKey))
    /// 隐藏 / 显示全部贴图（⇧F3）
    /// 放宽为 internal：热键扩展文件要用
    static let hideAllPinsCombo = HotKeyCombo(keyCode: UInt32(kVK_F3), modifiers: UInt32(shiftKey))
    /// 延时截图热键（⌥⇧D，3 秒后自动开始）
    /// 放宽为 internal：热键扩展文件要用
    static let delayedSnipCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_D),
                                                      modifiers: UInt32(optionKey | shiftKey))
    /// 延时截图等待时长
    /// 放宽为 internal：热键扩展文件要用
    static let delayedSnipDelay: UInt64 = 3_000_000_000

    init(captureService: any SnipCaptureServicing = ScreenCaptureService(),
         pinWindows: PinWindowController = PinWindowController(),
         hotKeys: HotKeyRegistry = HotKeyRegistry(),
         storage: KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger) {
        self.captureService = captureService
        self.pinWindows = pinWindows
        self.hotKeys = hotKeys
        self.storage = storage
        self.hotKeyPreferences = SnipHotKeyPreferences(storage: storage)
        self.logger = logger
    }

    /// 上次成功截图的选区
    /// 放宽为 internal：覆盖层装配扩展文件要读
    var lastSelection: CGRect? {
        SnipSelectionCoding.decode(storage.string(forKey: Self.lastSelectionKey))
    }

    /// 记录本次选区：既供下次按 R 复用，也进历史供逗号 / 句号循环
    private func remember(_ rect: CGRect) {
        storage.set(SnipSelectionCoding.encode(rect), forKey: Self.lastSelectionKey)
        let previous = SnipSelectionHistoryCoding.decode(storage.string(forKey: Self.historyKey))
        let next = SnipSelectionHistoryCoding.push(rect, into: previous)
        storage.set(SnipSelectionHistoryCoding.encode(next), forKey: Self.historyKey)
    }

    /// 历史选区
    /// 放宽为 internal：覆盖层装配扩展文件要读
    var selectionHistory: [CGRect] {
        SnipSelectionHistoryCoding.decode(storage.string(forKey: Self.historyKey))
    }

    // MARK: - 截图

    /// 热键说明（供设置窗展示）
    var hotKeySummary: String {
        SnipHotKeyAction.allCases.map { action in
            "\(action.displayName)：\(hotKeyPreferences.combo(for: action).displayString)"
        }.joined(separator: "\n") + "\n\n截图界面内：回车复制 · ⌘S 另存为 · ⌘⇧S 快速保存 · ⌘T 贴图\n"
             + "            R 上次区域 · ⌘A 全屏 · Tab 窗口检测 · 反引号 指针\n"
             + "            空格 显隐工具条 · ⌘Z / ⌘⇧Z 撤销重做"
    }

    /// 延时 3 秒后开始截图，便于先摆好要截的画面
    func beginDelayedSnip() {
        guard overlays.isEmpty else { return }
        logger.info("延时截图：3 秒后开始")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.delayedSnipDelay)
            self.beginSnip()
        }
    }

    func beginSnip() {
        // 已有覆盖层时再按一次：把键盘焦点抢回来，而不是静默什么都不做
        // （历史上这里直接 return，用户看到的就是「按了毫无反应」）
        guard overlays.isEmpty else {
            refocusOverlays()
            return
        }
        // 抓屏是异步的，这段空档里重复按热键会各开一套覆盖层（实测连按会叠出两层，
        // 按 Esc 只关掉一层，看起来就像「Esc 时灵时不灵」）。这里用一个进行中标志挡住重入。
        guard !isStarting else {
            logger.info("截图正在准备中，忽略重复触发的截图热键")
            return
        }
        isStarting = true
        defer { isStarting = false }
        guard captureService.isAuthorized() else {
            SnipPermissionGuide.present(logger: logger)
            return
        }
        // 抓屏本身要几百毫秒，这段空档正好用来把前台从原 App 抢过来。
        // 若等到覆盖层上屏才激活，第一下 Esc / 回车会投给原前台 App 而丢失
        // （实测：不提前抢前台时，每 5 轮会有 1~2 轮首下按键失效）。
        Task { @MainActor in
            // 抓屏必须发生在抢前台之前：
            // 1) 先切 .regular / activate 会让原 App 退到后台，菜单面板（NSPopover，transient）
            //    随之收起，紧接着抓屏拍到的就是「面板底下的背景」——用户口径「想截详情页，
            //    截出来的是背景」；
            // 2) 原 App 退场与覆盖层上屏之间会空出一段只看得见桌面的时间，就是「屏幕闪一下」。
            // 因此顺序改成「前台不动 → 抓屏 → 抢前台 → 上屏覆盖层」，
            // 保住了要截的画面，也把两帧之间的空白压到几乎不存在。
            do {
                let result = try await captureService.captureAllDisplays()
                guard !result.isEmpty else {
                    fail(message: "没有捕获到任何屏幕内容")
                    return
                }
                captures = result
                await self.claimForegroundForCapture()
                presentOverlays(result)
            } catch {
                fail(message: Self.failureDescription(error))
            }
        }
    }


    // MARK: - 覆盖层生命周期（实现在 SnipController+Overlay.swift）


    // MARK: - 覆盖层回调

    func overlayViewDidCancel(_ view: SnipOverlayView) {
        dismissOverlays()
    }

    func overlayViewDidToggleCursor(_ view: SnipOverlayView) {
        cursorIncluded.toggle()
        let includeCursor = cursorIncluded
        // 重新捕获时先把覆盖层透明掉，否则会把自己拍进截图
        for window in overlays { window.alphaValue = 0 }
        Task { @MainActor in
            defer { for window in overlays { window.alphaValue = 1 } }
            try? await Task.sleep(nanoseconds: 80_000_000)
            do {
                let result = try await captureService.captureAllDisplays(includeCursor: includeCursor)
                guard result.count == overlays.count else { return }
                captures = result
                for (window, captured) in zip(overlays, result) {
                    window.overlayView.updateScreenshot(captured.image)
                }
                logger.info("指针显示：\(includeCursor ? "开" : "关")")
            } catch {
                logger.error("切换指针后重捕失败：\(error)")
            }
        }
    }

    func overlayView(_ view: SnipOverlayView, didConfirm rect: CGRect) {
        guard let target = resolve(capturedFor: view, localRect: rect) else { return }
        let annotations = view.annotationsForComposition
        copyToPasteboard(target, annotations: annotations)
        remember(target.globalRect)
        // 设置页的「复制后自动保存」此前只落在偏好里、没有任何消费方：
        // 打开开关后截图依然只进剪贴板。这里补上唯一落盘出口。
        if storage.bool(forKey: SnipPreferenceKey.autoSaveAfterCopy),
           let cropped = composedImage(captured: target.captured,
                                      globalRect: target.globalRect,
                                      annotations: annotations) {
            persistQuietly(cropped)
        }
        dismissOverlays()
    }

    func overlayView(_ view: SnipOverlayView, didRequestSave rect: CGRect, quick: Bool) {
        guard let target = resolve(capturedFor: view, localRect: rect) else { return }
        // 保存必须与复制 / 贴图同一份产物：早期这里走的是「纯裁剪 + 把标注当参数传下去、
        // 下游却没消费」，画了矩形箭头再保存，文件里干干净净 —— 用户以为标注丢了。
        guard let cropped = composedImage(captured: target.captured,
                                          globalRect: target.globalRect,
                                          annotations: view.annotationsForComposition) else {
            logger.warning("保存失败：选区裁剪为空")
            return
        }
        if quick {
            saveQuickly(cropped)
        } else {
            // 面板会激活本 App，先收掉覆盖层避免面板被压在 screenSaver 层级之下
            dismissOverlays()
            presentSavePanel(for: cropped)
        }
    }

    func overlayView(_ view: SnipOverlayView, didRequestPin rect: CGRect) {
        guard let target = resolve(capturedFor: view, localRect: rect) else { return }
        if let image = composedImage(captured: target.captured,
                                     globalRect: target.globalRect,
                                     annotations: view.annotationsForComposition) {
            // 截图贴图没有来源文本（它来自像素选区），⌘⇧C 会明确告知「无内容可复制」
            pinWindows.pin(image: image, cgRect: target.globalRect, sourceText: nil)
        }
        remember(target.globalRect)
        dismissOverlays()
    }

    // MARK: - 坐标解析

    private func capturedFor(_ view: SnipOverlayView) -> SnipCapturedImage? {
        overlays.first { $0.overlayView === view }.flatMap { window in
            captures.first { captured in
                SelectionGeometry.appKitRect(fromCG: captured.display.frame,
                                             primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
                    == window.frame
            }
        }
    }

    private func resolve(capturedFor view: SnipOverlayView,
                         localRect: CGRect) -> (captured: SnipCapturedImage, globalRect: CGRect)? {
        guard let captured = capturedFor(view) else {
            logger.warning("找不到覆盖层对应的捕获图")
            return nil
        }
        let global = localRect.offsetBy(dx: captured.display.frame.minX,
                                        dy: captured.display.frame.minY)
        guard global.width >= 1, global.height >= 1 else { return nil }
        return (captured, global)
    }
}
