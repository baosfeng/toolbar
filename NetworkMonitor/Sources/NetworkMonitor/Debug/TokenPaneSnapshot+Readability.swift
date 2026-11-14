#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - Token 页可读性度量（从 TokenPaneSnapshot.swift 拆出：单文件体积门禁）

extension TokenPaneSnapshot {

    /// 导出 r3 可读性度量：字号 / 区块高度 / 内容总高 vs 520 / 分布行名称可用宽度与截断
    static func writeReadabilityMetrics(directory: URL, snapshot: HarnessUsageSnapshot) {
        let panel = MenuPanelView.evidencePanel()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.layoutSubtreeIfNeeded()
        let pane = panel.tokenPane
        var lines: [String] = []

        lines.append("# 字号（pt）")
        let fonts: [(String, NSFont)] = [
            ("hero.value", TokenPaneStyle.heroMainFont),
            ("hero.unit", TokenPaneStyle.heroMainUnitFont),
            ("hero.title", TokenPaneStyle.heroLabelFont),
            ("hero.delta", TokenPaneStyle.heroDeltaFont),
            ("hero.clock", TokenPaneStyle.heroClockFont),
            ("card.value", TokenPaneStyle.cardValueFont),
            ("card.title", TokenPaneStyle.cardTitleFont),
            ("card.aux", TokenPaneStyle.cardFooterFont),
            ("cardHead.title", TokenPaneStyle.cardHeadTitleFont),
            ("meta", TokenPaneStyle.metaFont),
            ("legend", TokenPaneStyle.legendFont),
            ("legend.value", TokenPaneStyle.legendValueFont),
            ("axis", TokenPaneStyle.axisFont),
            ("row.name", TokenPaneStyle.rowNameFont),
            ("row.value", TokenPaneStyle.rowValueFont),
            ("row.percent", TokenPaneStyle.rowPercentFont),
            ("ring.text", TokenPaneStyle.ringTextFont),
            ("state", TokenPaneStyle.stateFont),
            ("state.value", TokenPaneStyle.stateValueFont),
            ("segment", TokenPaneStyle.segmentFont),
            ("textButton", TokenPaneStyle.textButtonFont),
        ]
        for item in fonts {
            lines.append(String(format: "%@ = %.1f", item.0, item.1.pointSize))
        }

        lines.append("# Hero 实测（frame 相对 pane）")
        for item in pane.heroMetricsForSnapshot() {
            lines.append(String(format: "%@: fontSize=%.1f x=%.1f y=%.1f w=%.1f h=%.1f needed=%.1f text=%@",
                                item.name, item.fontSize, item.frame.minX, item.frame.minY,
                                item.frame.width, item.frame.height, item.needed, item.text))
        }

        lines.append("# 区块 frame（pane 坐标）")
        for item in pane.layoutMetricsForSnapshot() {
            lines.append(String(format: "%@: x=%.1f y=%.1f w=%.1f h=%.1f",
                                item.name, item.frame.minX, item.frame.minY,
                                item.frame.width, item.frame.height))
        }

        let needed = panel.desiredContentHeight
        lines.append("# 高度")
        lines.append(String(format: "content_needed_pt = %.0f", needed))
        lines.append(String(format: "popover_max_pt = %.0f", MenuPanelStyle.maxHeight))
        lines.append(String(format: "scrollable = %@", needed > MenuPanelStyle.maxHeight + 0.5 ? "YES" : "NO"))

        lines.append("# 项目 / 模型行名称可用宽度（needed > available 即截断）")
        for item in pane.distroRowMetricsForSnapshot() {
            lines.append(String(format: "%@: available=%.1f needed=%.1f truncated=%@ text=%@",
                                item.name, item.available, item.needed,
                                item.truncated ? "YES" : "NO", item.text))
        }

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-readability.txt"),
                        atomically: true, encoding: .utf8)
    }

}
#endif
