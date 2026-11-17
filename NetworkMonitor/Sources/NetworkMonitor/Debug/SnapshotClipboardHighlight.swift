#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 搜索命中高亮取证（仅 DEBUG）

/// 搜索高亮的离屏取证 —— 同一批夹具在「无查询」与「有查询」两种状态下各渲染一张
///
/// 触发：`NM_SNAPSHOT_CLIPBOARD_HIGHLIGHT=1 NM_SNAPSHOT_DIR=/tmp/<dir> <bundle 内可执行>`
/// 产出：`panel-clipboard-highlight-off.png` / `panel-clipboard-highlight-on.png`
/// 与一份区间自证文本（命中段数由产品自己的 `ClipboardSearchHighlight` 算出，不另写一套）。
@MainActor
enum SnapshotClipboardHighlight {

    /// 取证开关（与 NM_SNAPSHOT_DIR 组合使用）
    static let envKey = "NM_SNAPSHOT_CLIPBOARD_HIGHLIGHT"

    /// 画布尺寸（与其余剪贴板取证同一份）
    private static let canvasSize = SnapshotClipboardPanel.panelSize

    /// 取证查询串：多词 AND，两个词都在夹具里出现
    static let evidenceQuery = "swift Clipboard"

    /// 取证入口：开关打开时出「无查询 / 有查询」两张图 + 区间自证
    static func captureIfRequested(directory: URL) {
        guard ProcessInfo.processInfo.environment[envKey]?.isEmpty == false else { return }
        let logger = AppContext.shared.logger
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("高亮取证目录创建失败：\(error.localizedDescription)")
            return
        }
        let items = makeFixtureItems()
        render(items: items, query: "",
               to: directory.appendingPathComponent("panel-clipboard-highlight-off.png"))
        render(items: items, query: evidenceQuery,
               to: directory.appendingPathComponent("panel-clipboard-highlight-on.png"))
        writeStatus(directory: directory, items: items, logger: logger)
    }

    /// 渲染一个面板态：先灌查询让卡片按真实口径重绘，再布局
    private static func render(items: [ClipboardItem], query: String, to url: URL) {
        let canvas = SnapshotClipboardPanel(size: canvasSize, items: items).makeView()
        if let panel = canvas.subviews.compactMap({ $0 as? ClipboardPanelView }).first {
            panel.setQuery(query)
        }
        canvas.layoutSubtreeIfNeeded()
        MenuPanelSnapshot.render(view: canvas, size: canvasSize, appearanceName: .aqua, to: url)
    }

    // MARK: - 夹具

    /// 四条文本条目：正文里同时含查询的两个词，第二条只含一个词（取证明「不该全亮」）
    private static func makeFixtureItems() -> [ClipboardItem] {
        let now = SnapshotClock.now
        let specs = [
            "swift build --disable-sandbox 之后再看 Clipboard 面板",
            "Clipboard 面板的高亮只在搜索态出现",
            "swift run TestRunner 全绿",
            "https://api.example.com/v1/clipboard/status 里有断点",
        ]
        return specs.enumerated().map { index, text in
            ClipboardItem(kind: .text, text: text, preview: text,
                          contentHash: ClipboardContentHasher.hash(text: text) ?? "highlight-fixture-\(index)",
                          sourceBundleID: "com.apple.Terminal", sourceAppName: "终端",
                          createdAt: now.addingTimeInterval(Double(-index) * 60))
        }
    }

    // MARK: - 自证文本

    /// 区间自证：每条夹具在查询下的命中段数（与绘制走同一个纯函数）
    private static func writeStatus(directory: URL, items: [ClipboardItem], logger: LoggingService) {
        var lines = ["query = \(evidenceQuery)", "fixture_items = \(items.count)"]
        for (index, item) in items.enumerated() {
            let monospaced = ClipboardCardTextStyle.isMonospaced(item.preview)
            let display = ClipboardCardTextStyle.breakable(item.preview, monospaced: monospaced)
            let hits = ClipboardSearchHighlight.displayRanges(inDisplay: display, query: evidenceQuery)
            let sliced = hits.map { range in
                String(display[range]).replacingOccurrences(of: ClipboardCardTextStyle.zeroWidthSpace, with: "")
            }
            lines.append("item\(index)_hits = \(hits.count) \(sliced)")
        }
        let url = directory.appendingPathComponent("panel-clipboard-highlight-status.txt")
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("高亮取证状态写入失败：\(error.localizedDescription)")
        }
        logger.info("高亮取证完成：\(items.count) 条")
    }
}
#endif
