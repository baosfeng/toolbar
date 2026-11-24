#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

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
        case .cache: return "cache"
        case .hourly: return "hourly"
        case .bucket: return "bucket"
        case .trend: return "trend"
        }
    }

    /// 四张二级页各截「顶部 / 滚到底部」× 浅 / 深，并导出文档高度与视口高度
    ///
    /// 缓存命中原先是一整屏（取证在 +Cache），两屏收敛后降级为二级页，改由这里覆盖。
    /// 按项目 / 按模型没有独立页，它们是分布屏内的维度分段（取证见 +Distro）。
    ///
    /// 深色档必须一起出：这四页改前写死 .aqua，全机没有一张 menu-token-detail-*-dark.png，
    /// 「深色下二级页还读不读得全」就一直没有证据。
    ///
    /// 文件名沿用同一目录里其它 Token 快照的约定：浅色保持原名、深色加 "-dark" 后缀
    /// （menu-token-screen-* / menu-token-520-* 都是这么分的），既有引用不必跟着改。
    static func captureDetailPages(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for kind in TokenDetailKind.allCases {
            let slug = detailSlug(kind)
            for (appearance, appearanceSuffix) in TokenPaneSnapshot.appearancePasses {
                for suffix in ["top", "bottom"] {
                    let panel = tokenPanel(snapshot)
                    panel.tokenPane.openDetailForSnapshot(kind)
                    let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                    MenuPanelSnapshot.render(
                        view: panel, size: size, appearanceName: appearance,
                        to: directory.appendingPathComponent(
                            "menu-token-detail-\(slug)-\(suffix)\(appearanceSuffix).png"),
                        postLayout: { view in
                            guard let panel = view as? MenuPanelView else { return }
                            guard suffix == "bottom" else { return }
                            panel.tokenPane.detailPane.scrollToBottomForSnapshot()
                        })
                }
            }
            // 指标用独立实例量（渲染实例已被移出视图层级）
            let metricsPanel = tokenPanel(snapshot)
            metricsPanel.tokenPane.openDetailForSnapshot(kind)
            metricsPanel.layoutSubtreeIfNeeded()
            let metrics = metricsPanel.tokenPane.detailPane.snapshotScrollMetrics()
            lines.append(String(format: "%@: document=%.1f viewport=%.1f scrollable=%@ overflow=%.1f",
                                slug, metrics.document, metrics.viewport,
                                metrics.document > metrics.viewport + 0.5 ? "YES" : "NO",
                                metrics.document - metrics.viewport))
        }
        // 视口压到 300pt 的强制滚动自证，证明能滚到底（同样浅深两档）
        for (appearance, appearanceSuffix) in appearancePasses {
            for suffix in ["top", "bottom"] {
                let panel = tokenPanel(snapshot)
                panel.tokenPane.openDetailForSnapshot(.hourly)
                let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                MenuPanelSnapshot.render(
                    view: panel, size: size, appearanceName: appearance,
                    to: directory.appendingPathComponent(
                        "menu-token-detail-hourly-stress-\(suffix)\(appearanceSuffix).png"),
                    postLayout: { view in
                        guard let panel = view as? MenuPanelView else { return }
                        panel.tokenPane.detailPane.setViewportHeightForSnapshot(300)
                        if suffix == "bottom" { panel.tokenPane.detailPane.scrollToBottomForSnapshot() }
                    })
            }
        }
        let text = String(format: "panel = %dx%d, pane_max_height = %.1f, backbar = 20, gap = 6\n",
                          Int(MenuPanelStyle.panelWidth), Int(MenuPanelStyle.maxHeight),
                          TokenDetailPaneView.paneMaxHeight)
            + lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-detail-scroll-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }

    // MARK: - 小时卡 head 行取证

    /// 小时卡独立渲染（指定内容宽）× 浅 / 深 + 导出 head / meta 两行各元素 frame 与所需宽度
    ///
    /// 两档一起出：小时卡是唯一在 300pt 窄面板口径下也要复验的卡片，深色下贴底/截断的结论同样要能复看。
    /// 文字度量与外观无关，只在浅色档量一遍，深色档只补一张图。
    /// - Parameter name: 不含扩展名与外观后缀的文件基名（如 menu-token-hourcard-320）
    static func captureHourCard(directory: URL, snapshot: HarnessUsageSnapshot,
                                width: CGFloat, name: String) {
        let panel = tokenPanel(snapshot)
        panel.layoutSubtreeIfNeeded()
        let pane = panel.tokenPane
        let card = pane.hourCard
        let cardHeight = card.bounds.height
        card.removeFromSuperview()
        var lines: [String] = [String(format: "card_width = %.1f, card_height = %.1f", width, cardHeight)]
        for (appearance, appearanceSuffix) in appearancePasses {
            MenuPanelSnapshot.render(
                view: card, size: NSSize(width: width, height: cardHeight),
                appearanceName: appearance,
                to: directory.appendingPathComponent(name + appearanceSuffix + ".png"),
                postLayout: { view in
                    guard appearanceSuffix.isEmpty, let cardView = view as? TokenCardRow else { return }
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
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent(name + ".txt"),
                        atomically: true, encoding: .utf8)
    }
}
#endif
