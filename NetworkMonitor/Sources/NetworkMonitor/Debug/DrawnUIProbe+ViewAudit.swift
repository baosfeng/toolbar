#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 首屏视图台账（改造前后对账）

extension DrawnUIProbe {

    /// 打印「系统页首屏五卡 + 状态带」的视图台账 —— 改造前 / 改造后用同一条命令对账
    ///
    /// 触发：`NM_DRAWN_COUNT=<输出文件>`（可加 `NM_DRAWN_COUNT_TREE=1` 逐层输出 frame 与文字）
    /// 输出：每张卡内部视图数、五卡合计、状态带、总计；TREE=1 时附带完整视图树用于逐项核对几何。
    /// internal：入口 runIfRequested 在 DrawnUIProbe.swift，跨文件调用需放宽访问级别
    static func runViewAuditIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["NM_DRAWN_COUNT"], !path.isEmpty else {
            return false
        }
        // 剪贴板面板：`NM_DRAWN_COUNT_TAB=clipboard`（不设时仍量系统页，旧命令口径不变）
        if ProcessInfo.processInfo.environment["NM_DRAWN_COUNT_TAB"] == "clipboard" {
            return runClipboardViewAudit(path: path)
        }
        let panel = MenuPanelSnapshot.makeMenuPanel(tab: .system, items: [])
        let height = min(max(panel.desiredContentHeight, 180), MenuPanelStyle.maxHeight)
        let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drawn-view-audit-scratch.png")
        // 借快照渲染链路完成「进离屏窗口 → 布局 → 抓帧」，计数在 postLayout 回调里做
        MenuPanelSnapshot.render(view: panel, size: size, appearanceName: .aqua, to: scratch) { _ in
            let report = viewAuditReport(for: panel)
            try? report.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data(report.utf8))
            exit(0)
        }
        let failure = "视图台账：快照渲染未回调，未取到数据\n"
        try? failure.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(failure.utf8))
        exit(1)
    }

    /// 剪贴板面板视图台账：卡片区 / 卡片流 / 面板总计（与系统页同一套「子树 − 1」计数口径）
    ///
    /// 触发：`NM_DRAWN_COUNT=<文件> NM_DRAWN_COUNT_TAB=clipboard`
    /// 画布与取证快照同口径（640×260），条目夹具复用性能探针的 32 条（= 视图池窗口大小）。
    private static func runClipboardViewAudit(path: String) -> Bool {
        let items = ClipboardPerfProbe.fixtureItems()
        let size = SnapshotClipboardPanel.panelSize
        let canvas = SnapshotClipboardPanel(size: size, items: items).makeView()
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drawn-view-audit-clipboard.png")
        MenuPanelSnapshot.render(view: canvas, size: size, appearanceName: .aqua, to: scratch) { root in
            let report = ClipboardPerfProbe.viewLedger(root)
            try? report.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data(report.utf8))
            exit(0)
        }
        let failure = "剪贴板视图台账：快照渲染未回调，未取到数据\n"
        try? failure.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(failure.utf8))
        exit(1)
    }

    /// 台账正文：每卡内部视图数 + 状态带 + 总计（可选逐层视图树）
    private static func viewAuditReport(for panel: MenuPanelView) -> String {
        let pane = panel.systemPane
        let groups: [(String, NSView)] = [
            ("CPU 卡", pane.cpuCard),
            ("GPU 卡", pane.gpuCard),
            ("压力卡", pane.loadCard),
            ("内存卡", pane.memoryCard),
            ("磁盘卡", pane.diskCard),
            ("状态带", pane.stateBand),
        ]
        var lines = ["# 系统页首屏视图台账（五卡内部 + 20pt 状态带）", ""]
        lines.append("| 分组 | 内部视图数 | 含容器 | 面板内 frame |")
        lines.append("|------|-----------|--------|--------------|")
        var cardInterior = 0
        var allInterior = 0
        for (name, view) in groups {
            let subtree = subtreeCount(view)
            let interior = subtree - 1
            allInterior += interior
            if name != "状态带" { cardInterior += interior }
            let frame = view.convert(view.bounds, to: panel)
            lines.append("| \(name) | \(interior) | \(subtree) | "
                         + "(\(fmt(frame.minX)),\(fmt(frame.minY)),\(fmt(frame.width)),\(fmt(frame.height))) |")
        }
        lines.append("| **五卡合计** | **\(cardInterior)** | \(cardInterior + 5) | — |")
        lines.append("| **五卡 + 状态带** | **\(allInterior)** | \(allInterior + 6) | — |")
        // 首屏整体（四联 + 五卡 + 状态带）：对照「首屏视图数」这一口径
        if let firstScreen = pane.cpuTile.superview?.superview {
            lines.append("| 首屏整体（四联 + 五卡 + 状态带） | \(subtreeCount(firstScreen)) | — |")
        }
        lines.append("")
        lines.append("系统页高度：\(fmt(pane.fittingSize.height))pt，面板需求高度：\(fmt(panel.desiredContentHeight))pt")
        if ProcessInfo.processInfo.environment["NM_DRAWN_COUNT_TREE"]?.isEmpty == false {
            for (name, view) in groups {
                lines.append("")
                lines.append("## \(name) 视图树")
                lines.append("```")
                lines.append(contentsOf: viewAuditTree(of: view))
                lines.append("```")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 子树视图总数（含自身）
    private static func subtreeCount(_ view: NSView) -> Int {
        1 + view.subviews.reduce(0) { $0 + subtreeCount($1) }
    }

    /// 逐层视图树（坐标已换算到根视图，便于改造前后按同一坐标系核对）
    private static func viewAuditTree(of root: NSView) -> [String] {
        var out: [String] = []
        func walk(_ view: NSView, depth: Int) {
            let frame = view.convert(view.bounds, to: root)
            var line = String(repeating: "  ", count: depth) + "\(type(of: view))"
            if let field = view as? NSTextField {
                let fontName = field.font?.fontName ?? "-"
                line += " text=\"\(field.stringValue)\""
                line += " font=\(fmt(field.font?.pointSize ?? 0))/\(fontName)"
                line += " align=\(field.alignment.rawValue)"
            } else if let button = view as? NSButton {
                line += " title=\"\(button.title)\" font=\(fmt(button.font?.pointSize ?? 0))"
            }
            line += " frame=(\(fmt(frame.minX)),\(fmt(frame.minY)),\(fmt(frame.width)),\(fmt(frame.height)))"
            if view.isHidden { line += " hidden" }
            if let stack = view as? NSStackView {
                line += " spacing=\(fmt(stack.spacing))"
            }
            out.append(line)
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return out
    }

    /// 一位小数（台账里的几何值只到亚像素级）
    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
#endif
