#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 分布行取证（项目 / 模型 / 二级页整宽列表，仅 DEBUG）

/// 整宽列表分布行的截断与压行自证。
///
/// 证据口径：nameAvailable < nameNeeded = 名称被截断；valueAvailable < valueNeeded = 数值被截断；
/// nameHeight > rowHeight = 名称高过行高（换行 / 压行）。
@MainActor
extension TokenDetailPaneView {

    /// 页内分布行（按视图层级顺序）
    func distroRowsForSnapshot() -> [TokenDistroRowView] {
        layoutSubtreeIfNeeded()
        var result: [TokenDistroRowView] = []
        func walk(_ view: NSView) {
            if let row = view as? TokenDistroRowView {
                result.append(row)
                return
            }
            for subview in view.subviews { walk(subview) }
        }
        walk(self)
        return result
    }
}

@MainActor
extension TokenPaneSnapshot {

    /// 二级页「按项目 / 按模型」整宽列表 + 超长名压力行：导出每行可用宽度与所需宽度
    static func captureDistroRows(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for kind in [TokenDetailKind.projects, .models] {
            let panel = MenuPanelView()
            panel.updateToken(snapshot, notifySize: false)
            panel.select(tab: .token)
            panel.tokenPane.openDetailForSnapshot(kind)
            panel.layoutSubtreeIfNeeded()
            let pane = panel.tokenPane.detailPane
            let rows = pane.distroRowsForSnapshot()
            lines.append("# " + detailSlug(kind) + " 二级页整宽列表：" + String(rows.count) + " 行")
            for (index, row) in rows.enumerated() {
                lines.append(metricLine(index + 1, row.metricsForSnapshot(in: pane)))
            }
        }

        // 超长名压力行：同一行宽下把名称换成长 provider/model，验证「单行尾部省略」而非换行
        let probePanel = MenuPanelView()
        probePanel.updateToken(snapshot, notifySize: false)
        probePanel.select(tab: .token)
        probePanel.tokenPane.openDetailForSnapshot(.models)
        probePanel.layoutSubtreeIfNeeded()
        let probePane = probePanel.tokenPane.detailPane
        let rowWidth = probePane.distroRowsForSnapshot().first?.bounds.width ?? MenuPanelStyle.contentWidth
        let rowHeight = TokenPaneStyle.distroDetailRowHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight))
        let probe = TokenDistroRowView(height: rowHeight, stacked: false)
        container.addSubview(probe)
        NSLayoutConstraint.activate([
            probe.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            probe.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            probe.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        // 40 字符级超长名：整宽列表也放不下，必须走尾部省略
        let longName = "xiaomi-token-plan-cn/mimo-v2.5-pro-preview-long"
        probe.update(row: TokenDistroRow(rank: 1, name: longName,
                                         provider: "xiaomi-token-plan-cn",
                                         sub: "provider xiaomi-token-plan-cn · 占 41.2%" ,
                                         amount: "1.23B", share: 0.4123, colorIndex: 0))
        container.layoutSubtreeIfNeeded()
        lines.append("# 压力行：名称 " + longName + "（行宽 " + String(Int(rowWidth.rounded())) + "pt）")
        lines.append(metricLine(1, probe.metricsForSnapshot(in: container)))

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-detail-distro-rows.txt"),
                        atomically: true, encoding: .utf8)
    }

    /// 单行度量文本（名称 / 数值各给可用与所需宽度，超出即截断）
    private static func metricLine(_ index: Int,
                                   _ m: (available: CGFloat, needed: CGFloat, text: String, value: String,
                                         rowWidth: CGFloat, rowHeight: CGFloat, nameHeight: CGFloat,
                                         valueAvailable: CGFloat, valueNeeded: CGFloat)) -> String {
        var line = "row-" + String(index) + ": rowW=" + fmt(m.rowWidth) + " rowH=" + fmt(m.rowHeight)
        line += " | name [" + m.text + "] " + fmt(m.available) + "/" + fmt(m.needed)
        line += " h=" + fmt(m.nameHeight) + " truncated=" + (m.needed > m.available + 0.5 ? "YES" : "NO")
        line += " | value [" + m.value + "] " + fmt(m.valueAvailable) + "/" + fmt(m.valueNeeded)
        line += " truncated=" + (m.valueNeeded > m.valueAvailable + 0.5 ? "YES" : "NO")
        return line
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
#endif
