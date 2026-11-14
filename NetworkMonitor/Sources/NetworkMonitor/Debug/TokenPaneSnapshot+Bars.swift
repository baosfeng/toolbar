#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 柱图 / 键值行度量（仅 DEBUG）

/// 主图归一化基准与实际柱高、二级页键值行标题 / 数值宽度的取证入口。
///
/// 为什么会话图：柱「几乎贴底」这类问题只有在数值层量得出（基准取错 → 柱高比列高小一个量级），
/// 光看截图分不清「柱太矮」与「基准太大」，所以把基准与每列柱高一起落盘。
@MainActor
extension TokenPaneSnapshot {

    /// 主面板 24h 柱图（堆叠 / 请求数 / 对比三态）+ 二级页按小时柱图的基准与柱高
    static func writeBarMetrics(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        let states: [(name: String, hourView: TokenHourView, metric: TokenChartMetric)] = [
            ("stack", .stack, .total),
            ("request", .stack, .request),
            ("compare", .compare, .total),
        ]
        for state in states {
            let panel = MenuPanelView.evidencePanel()
            panel.updateToken(snapshot, notifySize: false)
            panel.select(tab: .token)
            panel.tokenPane.applyStateForSnapshot(range: .today, hourScope: .today,
                                                  trendMode: .stack,
                                                  hourView: state.hourView, metric: state.metric)
            panel.layoutSubtreeIfNeeded()
            lines.append("# 主面板 · " + state.name)
            appendBarLines(&lines, bar: panel.tokenPane.hourBars, label: "24h")
            appendLegendLine(&lines, legend: panel.tokenPane.hourLegend)
        }

        let detailPanel = MenuPanelView.evidencePanel()
        detailPanel.updateToken(snapshot, notifySize: false)
        detailPanel.select(tab: .token)
        detailPanel.tokenPane.openDetailForSnapshot(.hourly)
        detailPanel.layoutSubtreeIfNeeded()
        let bars = barViews(in: detailPanel.tokenPane.detailPane)
        lines.append("# 二级页 / 按小时：" + String(bars.count) + " 个柱图")
        for (index, bar) in bars.enumerated() {
            appendBarLines(&lines, bar: bar, label: "chart-" + String(index + 1))
        }

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-bar-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }

    /// 六个二级页的键值行（标题 / 数值可用宽度与所需宽度）
    static func writeKeyRowMetrics(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for kind in TokenDetailKind.allCases {
            let panel = MenuPanelView.evidencePanel()
            panel.updateToken(snapshot, notifySize: false)
            panel.select(tab: .token)
            panel.tokenPane.openDetailForSnapshot(kind)
            panel.layoutSubtreeIfNeeded()
            let pane = panel.tokenPane.detailPane
            let rows = keyRowViews(in: pane)
            lines.append("# " + detailSlug(kind) + "：" + String(rows.count) + " 行")
            for (index, row) in rows.enumerated() {
                let m = row.metricsForSnapshot(in: pane)
                var line = "row-" + String(index + 1) + ": rowW=" + fmt(m.rowWidth)
                    + " rowH=" + fmt(m.rowHeight)
                line += " | title [" + m.title + "] " + fmt(m.titleAvailable) + "/" + fmt(m.titleNeeded)
                line += " h=" + fmt(m.titleHeight)
                line += " truncated=" + (m.titleNeeded > m.titleAvailable + 0.5 ? "YES" : "NO")
                line += " | value [" + m.value + "] " + fmt(m.valueAvailable) + "/" + fmt(m.valueNeeded)
                line += " truncated=" + (m.valueNeeded > m.valueAvailable + 0.5 ? "YES" : "NO")
                lines.append(line)
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-keyrow-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }

    // MARK: - 内部

    /// 单张柱图的基准 / 柱高与「最高柱占绘图区比例」
    private static func appendBarLines(_ lines: inout [String], bar: TokenBarsView, label: String) {
        let metrics = bar.columnMetricsForSnapshot()
        let heights = metrics.columns.map { $0.height }
        let peak = heights.max() ?? 0
        let positive = heights.filter { $0 > 0 }
        let floor = positive.min() ?? 0
        let ratio = metrics.plotHeight > 0 ? peak / metrics.plotHeight : 0
        lines.append(label + ": shape=" + metrics.shape + " scale=" + String(metrics.scale)
            + " plot=" + fmt(metrics.plotHeight) + "pt peak=" + fmt(peak)
            + "pt floor(>0)=" + fmt(floor) + "pt peak/plot=" + String(format: "%.3f", ratio)
            + " columns=" + String(metrics.columns.count))
        for column in metrics.columns {
            lines.append("  col-" + String(format: "%02d", column.index)
                + " value=" + String(column.value) + " height=" + fmt(column.height) + "pt")
        }
    }

    /// 图例项数与内容（核对「对比态两项、堆叠态三条」与数据一致）
    private static func appendLegendLine(_ lines: inout [String], legend: TokenLegendRowView) {
        let items = legend.itemsForSnapshot()
        let text = items.map { item in
            item.title + " " + item.value + (item.dashed ? "(虚线)" : "（实心）")
        }
        lines.append("legend: " + String(items.count) + " 项 · " + text.joined(separator: " | "))
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private static func barViews(in view: NSView) -> [TokenBarsView] {
        var result: [TokenBarsView] = []
        func walk(_ node: NSView) {
            if let bar = node as? TokenBarsView {
                result.append(bar)
                return
            }
            for subview in node.subviews { walk(subview) }
        }
        walk(view)
        return result
    }

    private static func keyRowViews(in view: NSView) -> [TokenKeyRowView] {
        var result: [TokenKeyRowView] = []
        func walk(_ node: NSView) {
            if let row = node as? TokenKeyRowView {
                result.append(row)
                return
            }
            for subview in node.subviews { walk(subview) }
        }
        walk(view)
        return result
    }
}
#endif
