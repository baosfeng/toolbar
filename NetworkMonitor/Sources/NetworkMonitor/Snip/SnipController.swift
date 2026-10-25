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

    /// 截图热键（默认 F1，被占用时回落 ⌥⇧X）
    /// 放宽为 internal：热键扩展文件要用
    static let primarySnipCombo = HotKeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0)
    /// 放宽为 internal：热键扩展文件要用
    static let fallbackSnipCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_X),
                                                       modifiers: UInt32(optionKey | shiftKey))
    /// 贴图热键（默认 F3，被占用时回落 ⌥⇧P）
    /// 放宽为 internal：热键扩展文件要用
    static let primaryPinCombo = HotKeyCombo(keyCode: UInt32(kVK_F3), modifiers: 0)
    /// 放宽为 internal：热键扩展文件要用
    static let fallbackPinCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_P),
                                                      modifiers: UInt32(optionKey | shiftKey))
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
        self.logger = logger
    }

    /// 上次成功截图的选区
    private var lastSelection: CGRect? {
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
    private var selectionHistory: [CGRect] {
        SnipSelectionHistoryCoding.decode(storage.string(forKey: Self.historyKey))
    }

    // MARK: - 截图

    /// 热键说明（供设置窗展示）
    var hotKeySummary: String {
        [
            "F1        开始截图",
            "F3        贴图（图片 / 文件 / 颜色 / HTML / 文本）",
            "⇧F3       隐藏 / 显示全部贴图",
            "⌥⇧D       延时 3 秒截图",
            "⌥⇧V       剪贴板历史",
            "⌥⇧,       打开本设置窗",
            "",
            "截图界面内：回车复制 · ⌘S 另存为 · ⌘⇧S 快速保存 · ⌘T 贴图",
            "            R 上次区域 · ⌘A 全屏 · Tab 窗口检测 · 反引号 指针",
            "            空格 显隐工具条 · ⌘Z / ⌘⇧Z 撤销重做"
        ].joined(separator: "\n")
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
        guard overlays.isEmpty else { return }
        guard captureService.isAuthorized() else {
            SnipPermissionGuide.present(logger: logger)
            return
        }
        Task { @MainActor in
            do {
                let result = try await captureService.captureAllDisplays()
                captures = result
                presentOverlays(result)
            } catch {
                logger.error("截图失败：\(error)")
                captures = []
            }
        }
    }

    func presentOverlays(_ result: [SnipCapturedImage]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windowInfos = captureService.windowInfos()
        let previous = lastSelection
        let history = selectionHistory
        overlays = result.map { captured in
            SnipOverlayWindow(display: captured.display,
                              screenshot: captured.image,
                              windowInfos: windowInfos,
                              lastSelection: previous,
                              history: history,
                              primaryHeight: primaryHeight,
                              delegate: self)
        }
        overlays.forEach { $0.present() }
        logger.info("截图覆盖层已就绪，共 \(overlays.count) 屏")
    }

    /// 放宽为 internal：导出扩展文件保存后要收覆盖层
    func dismissOverlays() {
        for window in overlays {
            window.orderOut(nil)
            window.close()
        }
        overlays.removeAll()
        captures.removeAll()
    }

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
        copyToPasteboard(target, annotations: view.annotationsForComposition)
        remember(target.globalRect)
        dismissOverlays()
    }

    func overlayView(_ view: SnipOverlayView, didRequestSave rect: CGRect, quick: Bool) {
        guard let target = resolve(capturedFor: view, localRect: rect) else { return }
        guard let cropped = PinWindowController.crop(target.captured, to: target.globalRect) else {
            logger.warning("保存失败：选区裁剪为空")
            return
        }
        if quick {
            saveQuickly(cropped, annotations: view.annotationsForComposition)
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
            pinWindows.pin(image: image, cgRect: target.globalRect)
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
