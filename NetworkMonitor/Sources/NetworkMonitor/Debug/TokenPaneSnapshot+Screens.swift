#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 4 屏取证（浅 / 深，仅 DEBUG）

/// 分屏后的核心验收是「每屏单独看读不读得全」，并且**四屏高度必须一致**
/// （否则用户切屏时 popover 跳高跳低）。截图证明没裁切，量值证明没挤压、没跳动。
@MainActor
extension TokenPaneSnapshot {

    /// 概览 / 用量 / 缓存 / 排行各截浅深两张 + 一份「屏 → 区块 / 页脚 / 高度」台账
    static func captureScreens(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        var heights: [(slug: String, height: CGFloat)] = []
        var fills: [(slug: String, ratio: CGFloat, blank: CGFloat)] = []
        for screen in TokenScreen.allCases {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                let panel = makeScreenPanel(snapshot: snapshot, screen: screen)
                let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                MenuPanelSnapshot.render(view: panel, size: size, appearanceName: appearance,
                                         to: directory.appendingPathComponent(
                                            "menu-token-screen-\(screenSlug(screen))-\(name).png"))
            }
            let metrics = screenMetricsLines(snapshot: snapshot, screen: screen)
            let metricsPanel = makeScreenPanel(snapshot: snapshot, screen: screen)
            heights.append((screenSlug(screen), metricsPanel.tokenPane.fittingSize.height))
            if let frame = metricsPanel.tokenPane.screenFrames[safe: screen.rawValue] {
                let scroll = frame.snapshotScrollMetrics()
                let ratio = scroll.viewport > 0 ? scroll.document / scroll.viewport * 100 : 0
                fills.append((screenSlug(screen), ratio, max(0, scroll.viewport - scroll.document)))
            }
            lines.append(contentsOf: metrics)
        }
        // 四屏高度是否恒定（切屏不跳高跳低的直接证据）
        let distinct = Set(heights.map { Int($0.height.rounded()) })
        lines.append("# 四屏 pane 高度：" + heights.map { $0.slug + "=" + fmt($0.height) }.joined(separator: " · "))
        lines.append("# pane 高度一致 = " + (distinct.count == 1 ? "YES" : "NO"))
        lines.append("# 内容占可视区比例：" + fills.map {
            $0.slug + "=" + String(format: "%.1f%%", $0.ratio)
        }.joined(separator: " · "))
        lines.append("# 剩余空白：" + fills.map {
            $0.slug + "=" + String(format: "%.1fpt", $0.blank)
        }.joined(separator: " · "))
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-screens.txt"),
                        atomically: true, encoding: .utf8)
        AppContext.shared.logger.info("Token 4 屏取证完成（浅 / 深 × 概览 / 用量 / 缓存 / 排行）")
    }

    // MARK: - 内部

    /// 切到指定屏的面板（截图与台账共用同一条链路）
    private static func makeScreenPanel(snapshot: HarnessUsageSnapshot,
                                        screen: TokenScreen) -> MenuPanelView {
        let panel = MenuPanelView.evidencePanel()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.tokenPane.selectScreenForSnapshot(screen)
        panel.layoutSubtreeIfNeeded()
        return panel
    }

    /// 单屏台账：契约区块顺序 + 页脚 + 屏高 / 内容高 / 视口 + 各块 frame
    private static func screenMetricsLines(snapshot: HarnessUsageSnapshot,
                                           screen: TokenScreen) -> [String] {
        let panel = makeScreenPanel(snapshot: snapshot, screen: screen)
        panel.layoutSubtreeIfNeeded()
        let pane = panel.tokenPane
        var lines: [String] = ["# " + screen.title + "（" + screenSlug(screen) + "）"]
        lines.append("blocks: " + TokenScreen.blocks(for: screen).map { $0.title }.joined(separator: " → "))
        lines.append("footer: " + screen.footer.title)
        lines.append(String(format: "pane_height = %.1f content_needed = %.0f popover_max = %.0f outer_scrollable = %@",
                            pane.fittingSize.height, panel.desiredContentHeight, MenuPanelStyle.maxHeight,
                            panel.desiredContentHeight > MenuPanelStyle.maxHeight + 0.5 ? "YES" : "NO"))
        if screen == .ranking {
            let rows = pane.rankScreen.rowMetricsForSnapshot()
            lines.append(String(format: "ranking_rows = %d row_height = %.1fpt row_blank = %.1fpt (min %.0f / max %.0f)",
                                rows.visible, rows.rowHeight, rows.blank,
                                TokenRankingScreenView.minRowHeight,
                                TokenRankingScreenView.maxRowHeight))
            lines.append("ranking_parts = " + pane.rankScreen.cardPartsForSnapshot())
        }
        if screen == .usage {
            lines.append(String(format: "chart_hourly_height = %.1f chart_trend_height = %.1f",
                                pane.hourBars.bounds.height, pane.trendSpark.bounds.height))
        }
        if let frame = pane.screenFrames[safe: screen.rawValue] {
            let scroll = frame.snapshotScrollMetrics()
            // 内容占可视区多少、还剩多少空白（验收「空间有没有用好」的量化口径）
            let ratio = scroll.viewport > 0 ? scroll.document / scroll.viewport * 100 : 0
            let blank = max(0, scroll.viewport - scroll.document)
            lines.append(String(format: "screen_frame = %.1f footer_height = %.1f content = %.1f viewport = %.1f fill_ratio = %.1f%% blank = %.1fpt inner_scrollable = %@",
                                frame.bounds.height, frame.footer.bounds.height, scroll.document,
                                scroll.viewport, ratio, blank,
                                frame.isContentScrollable ? "YES" : "NO"))
            for (index, card) in frame.content.arrangedSubviews.enumerated() {
                let rect = card.convert(card.bounds, to: pane)
                lines.append(String(format: "%@-block-%d: x=%.1f y=%.1f w=%.1f h=%.1f",
                                    screenSlug(screen), index, rect.minX, rect.minY,
                                    rect.width, rect.height))
            }
        }
        for item in pane.layoutMetricsForSnapshot() {
            lines.append(String(format: "%@: x=%.1f y=%.1f w=%.1f h=%.1f",
                                item.name, item.frame.minX, item.frame.minY,
                                item.frame.width, item.frame.height))
        }
        return lines
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    /// 文件名后缀
    private static func screenSlug(_ screen: TokenScreen) -> String {
        switch screen {
        case .overview: return "overview"
        case .usage: return "usage"
        case .cache: return "cache"
        case .ranking: return "ranking"
        }
    }
}
#endif
