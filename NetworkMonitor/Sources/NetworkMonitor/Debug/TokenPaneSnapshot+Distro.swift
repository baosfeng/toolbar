#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 排行屏分布行取证（项目 / 模型两维度，仅 DEBUG）

/// 整宽列表分布行的截断与压行自证。
///
/// 证据口径：nameAvailable < nameNeeded = 名称被截断；valueAvailable < valueNeeded = 数值被截断；
/// nameHeight > rowHeight = 名称高过行高（换行 / 压行）。
@MainActor
extension TokenPaneSnapshot {

    /// 排行屏「项目 / 模型」两个维度的整宽列表 + 超长名压力行
    ///
    /// 这两个维度改前各有一个二级页，现在合成一屏由分段切换；两档都量，
    /// 免得「按模型」那档因为没被点开而漏掉截断证据。
    static func captureDistroRows(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for dimension in [TokenDistroDimension.projects, .models] {
            let panel = makeRankingPanel(snapshot: snapshot, dimension: dimension)
            panel.layoutSubtreeIfNeeded()
            let screen = panel.tokenPane.rankScreen
            let rows = screen.rowsForSnapshot.filter { !$0.isHidden }
            lines.append("# 排行屏 " + distroSlug(dimension) + " 整宽列表：" + String(rows.count) + " 行")
            for (index, row) in rows.enumerated() {
                lines.append(metricLine(index + 1, row.metricsForSnapshot(in: screen)))
            }
        }

        // 超长名压力行：同一行宽下把名称换成长 provider/model，验证「单行尾部省略」而非换行
        let probePanel = makeRankingPanel(snapshot: snapshot, dimension: .models)
        probePanel.layoutSubtreeIfNeeded()
        let probeScreen = probePanel.tokenPane.rankScreen
        let rowWidth = probeScreen.rowsForSnapshot.first?.bounds.width ?? MenuPanelStyle.contentWidth
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
                                         sub: "provider xiaomi-token-plan-cn · 占 41.2%",
                                         amount: "1.23B", share: 0.4123, colorIndex: 0))
        container.layoutSubtreeIfNeeded()
        lines.append("# 压力行：名称 " + longName + "（行宽 " + String(Int(rowWidth.rounded())) + "pt）")
        lines.append(metricLine(1, probe.metricsForSnapshot(in: container)))

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-detail-distro-rows.txt"),
                        atomically: true, encoding: .utf8)
    }

    // MARK: - 内部

    /// 切到排行屏并指定维度的面板
    private static func makeRankingPanel(snapshot: HarnessUsageSnapshot,
                                        dimension: TokenDistroDimension) -> MenuPanelView {
        let panel = MenuPanelView.evidencePanel()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.tokenPane.selectScreenForSnapshot(.ranking)
        panel.tokenPane.rankScreen.setDimensionForSnapshot(dimension)
        if let model = panel.tokenPane.lastModel { panel.tokenPane.rankScreen.update(model: model) }
        return panel
    }

    /// 维度后缀（文件名 / 台账用）
    private static func distroSlug(_ dimension: TokenDistroDimension) -> String {
        dimension == .projects ? "projects" : "models"
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
