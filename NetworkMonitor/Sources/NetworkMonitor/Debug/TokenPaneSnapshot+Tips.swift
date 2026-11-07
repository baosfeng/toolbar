#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 分布行 / 图例 / 占比条悬停文案取证（仅 DEBUG）

/// 悬停文案落盘自证。
///
/// 为什么要这个文件：同一模型（如 deepseek-v4.1-flash）来自多个 provider 时，主面板半宽卡的
/// 可见正文只写模型名、两行一模一样；provider 只在 toolTip 里，而 toolTip 不落盘就等于没有证据。
/// 这里把「主面板项目/模型卡每一行」「二级页整宽列表每一行」「占比条整条」「图例每一项」
/// 当前真正挂上去的 toolTip 原样导出，供复验时逐条比对，不重算文案（重算会掩盖接线错误）。
@MainActor
extension TokenPaneSnapshot {

    /// 导出每行 / 每条 / 每项的悬停文案到 menu-token-tips.txt
    static func captureHoverTips(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []

        // 1. 主面板：项目卡 / 模型卡的半宽行（这里是 provider 唯一可见的地方）
        let panel = MenuPanelView()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.layoutSubtreeIfNeeded()
        let pane = panel.tokenPane
        for (block, rows) in [("project", pane.projectRows), ("model", pane.modelRows)] {
            lines.append("# 主面板 · " + (block == "project" ? "按项目" : "按模型") + " 卡（半宽行）")
            for (index, row) in rows.enumerated() where !row.isHidden {
                lines.append(singleLine(index + 1, tip: row.toolTipForSnapshot))
            }
        }
        lines.append("# 主面板 · 占比条整条")
        lines.append("projectBar: " + flatten(pane.projectBar.toolTipForSnapshot))
        lines.append("modelBar: " + flatten(pane.modelBar.toolTipForSnapshot))

        // 2. 二级页：整宽列表行 + 顶部占比条 + 图例项
        for kind in [TokenDetailKind.projects, .models] {
            let detailPanel = MenuPanelView()
            detailPanel.updateToken(snapshot, notifySize: false)
            detailPanel.select(tab: .token)
            detailPanel.tokenPane.openDetailForSnapshot(kind)
            detailPanel.layoutSubtreeIfNeeded()
            let detailPane = detailPanel.tokenPane.detailPane
            lines.append("# 二级页 " + detailSlug(kind) + " · 整宽列表")
            for (index, row) in detailPane.distroRowsForSnapshot().enumerated() {
                lines.append(singleLine(index + 1, tip: row.toolTipForSnapshot))
            }
            let bars = detailStackBars(in: detailPane)
            lines.append("# 二级页 " + detailSlug(kind) + " · 占比条 " + String(bars.count) + " 条")
            for (index, bar) in bars.enumerated() {
                lines.append("bar-" + String(index + 1) + ": " + flatten(bar.toolTipForSnapshot))
            }
            for (index, legend) in detailLegends(in: detailPane).enumerated() {
                lines.append("legend-" + String(index + 1) + ": " + flatten(legend.toolTipForSnapshot))
            }
        }

        let text = lines.joined(separator: "\n") + "\n"
        do {
            try text.write(to: directory.appendingPathComponent("menu-token-tips.txt"),
                           atomically: true, encoding: .utf8)
        } catch {
            AppContext.shared.logger.error("Token 快照：悬停文案写入失败 \(error.localizedDescription)")
        }
    }

    // MARK: - 内部

    private static func singleLine(_ index: Int, tip: String) -> String {
        "row-" + String(index) + ": " + flatten(tip)
    }

    /// 多行 toolTip 压成一行（导出文件按行读，行内用 " ⏎ " 标出原来的断行位置）
    private static func flatten(_ tip: String) -> String {
        tip.isEmpty ? "(空)" : tip.replacingOccurrences(of: "\n", with: " ⏎ ")
    }

    private static func detailStackBars(in view: NSView) -> [TokenStackBarView] {
        var result: [TokenStackBarView] = []
        func walk(_ node: NSView) {
            if let bar = node as? TokenStackBarView {
                result.append(bar)
                return
            }
            for subview in node.subviews { walk(subview) }
        }
        walk(view)
        return result
    }

    private static func detailLegends(in view: NSView) -> [TokenLegendRowView] {
        var result: [TokenLegendRowView] = []
        func walk(_ node: NSView) {
            if let legend = node as? TokenLegendRowView {
                result.append(legend)
                return
            }
            for subview in node.subviews { walk(subview) }
        }
        walk(view)
        return result
    }
}
#endif
