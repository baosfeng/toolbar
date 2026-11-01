#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - Token 二级页与小时卡取证（从 TokenPaneSnapshot 拆出：单文件体积门禁）

/// 二级页滚动 / 小时卡 head 行的取证入口。
///
/// 成员由 private 放宽为 internal：同一类型的扩展分布在两个文件，跨文件访问需要 internal。
@MainActor
extension TokenPaneSnapshot {

    // MARK: - 二级页滚动取证

    /// 二级页文件后缀（与页面名一一对应）
    static func detailSlug(_ kind: TokenDetailKind) -> String {
        switch kind {
        case .hourly: return "hourly"
        case .bucket: return "bucket"
        case .trend: return "trend"
        case .cache: return "cache"
        case .projects: return "projects"
        case .models: return "models"
        }
    }

    /// 六个二级页各截「顶部 / 滚到底部」两张，并导出文档高度与视口高度
    static func captureDetailPages(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for kind in TokenDetailKind.allCases {
            let slug = detailSlug(kind)
            for suffix in ["top", "bottom"] {
                let panel = MenuPanelView()
                panel.updateToken(snapshot, notifySize: false)
                panel.select(tab: .token)
                panel.tokenPane.openDetailForSnapshot(kind)
                let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                MenuPanelSnapshot.render(
                    view: panel, size: size, appearanceName: .aqua,
                    to: directory.appendingPathComponent("menu-token-detail-\(slug)-\(suffix).png"),
                    postLayout: { view in
                        guard let panel = view as? MenuPanelView else { return }
                        guard suffix == "bottom" else { return }
                        panel.tokenPane.detailPane.scrollToBottomForSnapshot()
                    })
            }
            // 指标用独立实例量（渲染实例已被移出视图层级）
            let metricsPanel = MenuPanelView()
            metricsPanel.updateToken(snapshot, notifySize: false)
            metricsPanel.select(tab: .token)
            metricsPanel.tokenPane.openDetailForSnapshot(kind)
            metricsPanel.layoutSubtreeIfNeeded()
            let metrics = metricsPanel.tokenPane.detailPane.snapshotScrollMetrics()
            lines.append(String(format: "%@: document=%.1f viewport=%.1f scrollable=%@ overflow=%.1f",
                                slug, metrics.document, metrics.viewport,
                                metrics.document > metrics.viewport + 0.5 ? "YES" : "NO",
                                metrics.document - metrics.viewport))
        }
        // 视口压到 300pt 的强制滚动自证（内容 377 > 视口 274），证明能滚到底
        for suffix in ["top", "bottom"] {
            let panel = MenuPanelView()
            panel.updateToken(snapshot, notifySize: false)
            panel.select(tab: .token)
            panel.tokenPane.openDetailForSnapshot(.hourly)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
            MenuPanelSnapshot.render(
                view: panel, size: size, appearanceName: .aqua,
                to: directory.appendingPathComponent("menu-token-detail-hourly-stress-\(suffix).png"),
                postLayout: { view in
                    guard let panel = view as? MenuPanelView else { return }
                    panel.tokenPane.detailPane.setViewportHeightForSnapshot(300)
                    if suffix == "bottom" { panel.tokenPane.detailPane.scrollToBottomForSnapshot() }
                })
        }
        let text = String(format: "panel = %dx%d, pane_max_height = %.1f, backbar = 20, gap = 6\n",
                          Int(MenuPanelStyle.panelWidth), Int(MenuPanelStyle.maxHeight),
                          TokenDetailPaneView.paneMaxHeight)
            + lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-detail-scroll-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }

    // MARK: - 小时卡 head 行取证

    /// 小时卡独立渲染（指定内容宽）+ 导出 head / meta 两行各元素 frame 与所需宽度
    static func captureHourCard(directory: URL, snapshot: HarnessUsageSnapshot,
                                        width: CGFloat, name: String) {
        let panel = MenuPanelView()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.layoutSubtreeIfNeeded()
        let pane = panel.tokenPane
        let card = pane.hourCard
        let cardHeight = card.bounds.height
        card.removeFromSuperview()
        var lines: [String] = [String(format: "card_width = %.1f, card_height = %.1f", width, cardHeight)]
        MenuPanelSnapshot.render(view: card, size: NSSize(width: width, height: cardHeight),
                                 appearanceName: .aqua,
                                 to: directory.appendingPathComponent(name),
                                 postLayout: { view in
            guard let cardView = view as? TokenCardRow else { return }
            var rowPrefix = ""
            var previous: NSRect?
            for item in pane.hourCardMetricsForSnapshot(in: cardView) {
                let prefix = String(item.name.prefix(4))
                let sameRow = prefix == rowPrefix
                let gap = (sameRow ? previous.map { item.frame.minX - $0.maxX } : nil) ?? 0
                lines.append(String(format:
                                    "%@ \"%@\": x=%.1f w=%.1f needed=%.1f gap=%.1f truncated=%@",
                                    item.name, item.text, item.frame.minX, item.frame.width,
                                    item.needed, gap,
                                    item.needed > item.frame.width + 0.5 ? "YES" : "NO"))
                rowPrefix = prefix
                previous = item.frame
            }
        })
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent(name.replacingOccurrences(of: ".png", with: ".txt")),
                        atomically: true, encoding: .utf8)
    }
}
#endif
