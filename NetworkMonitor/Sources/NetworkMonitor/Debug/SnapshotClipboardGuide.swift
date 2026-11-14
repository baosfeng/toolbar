#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板首次引导态与快捷键帮助浮层取证（仅 DEBUG）

/// 两张面板态的离屏取证：首次引导态、快捷键帮助浮层
///
/// 触发：`NM_SNAPSHOT_CLIPBOARD_GUIDE=1 NM_SNAPSHOT_DIR=/tmp/<dir> <bundle 内可执行>`
/// 产出一张 640×260 浅色 PNG（引导 + 帮助浮层）与一份自证文本。
///
/// 存在理由：两种状态都由运行时状态驱动（偏好标记、浮层显隐），静态快照拿不到；
/// 这里复用产品自己的画布 `SnapshotClipboardPanel` 与面板视图 API，不另造一套界面。
@MainActor
enum SnapshotClipboardGuide {

    /// 取证开关（与 `NM_SNAPSHOT_DIR` 组合使用）
    static let envKey = "NM_SNAPSHOT_CLIPBOARD_GUIDE"

    /// 画布尺寸（与 07-contract 的剪贴板画布一致）
    private static let canvasSize = NSSize(width: 640, height: 260)
    /// 窄画布：面板最窄 420pt，用于验证帮助浮层两列不压字
    private static let narrowCanvasSize = NSSize(width: 420, height: 260)

    /// 取证入口：开关打开时出引导态与帮助浮层两张图
    static func captureIfRequested(directory: URL) {
        guard ProcessInfo.processInfo.environment[envKey]?.isEmpty == false else { return }
        let logger = AppContext.shared.logger
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("剪贴板引导取证目录创建失败：\(error.localizedDescription)")
            return
        }
        // 引导态：历史为空（items 传空），由面板 API 显式打开引导层
        let guideCanvas = SnapshotClipboardPanel(size: canvasSize, items: []).makeView()
        let guidePanel = guideCanvas.subviews.compactMap { $0 as? ClipboardPanelView }.first
        guidePanel?.updateGuideState(visible: true, toggleHotKey: HotKeyCombo.defaultPanelToggle.displayString)
        guideCanvas.layoutSubtreeIfNeeded()
        MenuPanelSnapshot.render(view: guideCanvas, size: canvasSize, appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-guide.png"))

        // 帮助浮层：有内容的面板上弹出键位卡片
        let helpCanvas = SnapshotClipboardPanel(size: canvasSize, items: []).makeView()
        let helpPanel = helpCanvas.subviews.compactMap { $0 as? ClipboardPanelView }.first
        helpPanel?.updateGuideState(visible: false, toggleHotKey: HotKeyCombo.defaultPanelToggle.displayString)
        helpPanel?.showShortcutHelp()
        helpCanvas.layoutSubtreeIfNeeded()
        MenuPanelSnapshot.render(view: helpCanvas, size: canvasSize, appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-shortcut-help.png"))

        // 窄面板档：面板宽度下限 420pt，浮层两列必须仍不压字
        let narrowCanvas = SnapshotClipboardPanel(size: narrowCanvasSize, items: []).makeView()
        narrowCanvas.subviews.compactMap { $0 as? ClipboardPanelView }.first?.showShortcutHelp()
        narrowCanvas.layoutSubtreeIfNeeded()
        MenuPanelSnapshot.render(view: narrowCanvas, size: narrowCanvasSize, appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-shortcut-help-narrow.png"))

        writeStatus(directory: directory, logger: logger)
    }

    /// 自证文本：键位数与引导文案口径，避免结论只靠肉眼
    private static func writeStatus(directory: URL, logger: LoggingService) {
        let keys = ClipboardShortcutHelp.entries.map(\.keys).joined(separator: " / ")
        let text = """
        guide_first_line = \(ClipboardGuideText.firstLine)
        guide_second_line = \(ClipboardGuideText.secondLine)
        guide_toggle_capsule = \(HotKeyCombo.defaultPanelToggle.displayString)
        shortcut_entries = \(ClipboardShortcutHelp.entries.count)
        shortcut_keys = \(keys)
        """ + "\n"
        let url = directory.appendingPathComponent("panel-clipboard-guide-status.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("剪贴板引导取证状态写入失败：\(error.localizedDescription)")
        }
        logger.info("剪贴板引导取证完成：键位 \(ClipboardShortcutHelp.entries.count) 条")
    }
}
#endif