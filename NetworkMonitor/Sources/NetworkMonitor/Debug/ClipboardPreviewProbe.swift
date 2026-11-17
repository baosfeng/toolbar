#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板预览实机自证（仅 DEBUG）

/// 预览浮层的实机取证 —— 真开面板、真预览、真抓屏
///
/// 触发：`NM_CLIPBOARD_PREVIEW_PROBE=<输出目录>`
/// 产出：`clipboard-preview-open.png`（文本预览）/ `clipboard-preview-image.png`（图片预览）/
/// `clipboard-preview-closed.png`（对照）/ `clipboard-preview-probe.txt`（可见性与 key 状态）。
///
/// 直接调与按键拦截同一个入口（`togglePreview`），不走合成按键：碳热键与合成键盘对
/// nonactivating 面板不可靠，而事件分发本身由 `handleKeyDown` 负责（本探针不改那条路径）。
@MainActor
enum ClipboardPreviewProbe {

    /// 探针开关
    static let envKey = "NM_CLIPBOARD_PREVIEW_PROBE"

    static func runIfRequested(coordinator: AppCoordinator) -> Bool {
        guard let directory = ProcessInfo.processInfo.environment[envKey], !directory.isEmpty else {
            return false
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let panel = coordinator.clipboardPanel
        // 必须晚于 schedulePrewarm 的 1.2s 预热（预热会开一次 popover 再关，抢走 key 会让面板收起）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // 直接执行二进制启动时进程不是前台 app，nonactivating 面板拿不到 key 会被
            // windowDidResignKey 收起；先激活自己再展开，与点状态栏唤起的时序等价
            NSApp.activate(ignoringOtherApps: true)
            panel?.toggle()
            panel?.content.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                runAfterOpen(panel: panel, directory: url)
            }
        }
        return true
    }

    /// 面板打开后：文本条目预览 → 图片条目预览 → 关预览抓对照
    private static func runAfterOpen(panel: ClipboardPanelController?, directory: URL) {
        guard let panel else { exit(2) }
        if panel.filteredItems.isEmpty { injectFixture(into: panel) }
        guard !panel.filteredItems.isEmpty else {
            write(["filtered_items = 0（库中没有条目，无法预览）"], to: directory)
            exit(3)
        }
        var lines = ["filtered_items = \(panel.filteredItems.count)",
                     "activation_policy = \(NSApp.activationPolicy().rawValue)"]
        let textOpened = panel.togglePreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let item = panel.selectedItem
            lines.append("text_toggle = \(textOpened) kind = \(item?.kind.rawValue ?? "nil")")
            lines.append(state(panel: panel, label: "文本预览打开"))
            shot(to: directory.appendingPathComponent("clipboard-preview-open.png"))
            panel.closePreview()
            guard let index = panel.filteredItems.firstIndex(where: { $0.isImage }) else {
                finish(panel: panel, directory: directory, lines: lines + ["image_item = 库中没有图片条目"])
                return
            }
            panel.panelView(panel.content, didSelect: index, click: .replace)
            _ = panel.togglePreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let image = panel.selectedItem
                lines.append("image_index = \(index) image_path = \(image?.imagePath ?? "—") "
                             + "ocr = \(image?.hasOCRText == true ? "有" : "无")")
                lines.append(state(panel: panel, label: "图片预览打开"))
                shot(to: directory.appendingPathComponent("clipboard-preview-image.png"))
                finish(panel: panel, directory: directory, lines: lines)
            }
        }
    }

    /// 关预览 + 抓对照图 + 落盘结论
    private static func finish(panel: ClipboardPanelController, directory: URL, lines: [String]) {
        panel.closePreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            var out = lines
            out.append(state(panel: panel, label: "预览关闭"))
            shot(to: directory.appendingPathComponent("clipboard-preview-closed.png"))
            write(out, to: directory)
            exit(0)
        }
    }

    /// 注入一条内存文本条目并重新过滤（只走渲染路径，不写数据库）
    private static func injectFixture(into panel: ClipboardPanelController) {
        let text = "空格预览自证：这是一条不落库的内存条目。\n第二行用于验证多行正文的换行与滚动。"
        panel.items.insert(ClipboardItem(kind: .text, text: text, preview: text,
                                         contentHash: "preview-probe-fixture",
                                         sourceBundleID: "com.apple.Terminal",
                                         sourceAppName: "终端"), at: 0)
        panel.applyFilter()
    }

    /// 面板与浮层的可见性 / key / 层级快照
    private static func state(panel: ClipboardPanelController, label: String) -> String {
        let preview = panel.previewWindow
        // 面板窗口经内容视图反查：探针不碰控制器私有成员
        let host = panel.content.window
        let keyWindow = NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil"
        return """
        [\(label)]
          panel_visible = \(host?.isVisible ?? false)
          panel_is_key = \(host?.isKeyWindow ?? false)
          panel_level = \(host?.level.rawValue ?? -1)
          preview_visible = \(preview?.isVisible ?? false)
          preview_level = \(preview.map { "\($0.level.rawValue)" } ?? "—")
          preview_is_child = \(host?.childWindows?.contains { $0 === preview } ?? false)
          app_key_window = \(keyWindow)
        """
    }

    /// 抓整屏（浮层是独立窗口，截整屏才能同时看到面板与浮层的关系）
    private static func shot(to url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func write(_ lines: [String], to directory: URL) {
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("clipboard-preview-probe.txt"),
                        atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(text.utf8))
    }
}
#endif
