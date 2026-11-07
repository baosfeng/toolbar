#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 缓存命中二级页三档范围取证（仅 DEBUG，从 TokenPaneSnapshot 拆出：单文件体积门禁）

/// 为什么单独取证：这页此前是「主数值今日 / 走势与均值 30 天 / 逐桶今日 24 桶」的混合口径，
/// 用户要求「我选择 7 天就只展示 7 天的」。三档范围各截一张 + 一份数值文案台账，
/// 才能证明「换范围真的换了数据」而不是换了个标题。
@MainActor
extension TokenPaneSnapshot {

    /// 三档范围 × 缓存命中二级页：顶部 / 滚到底部各一张，外加数值与文案台账
    static func captureCachePage(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for range in TokenRange.allCases {
            let slug = cacheSlug(range)
            for suffix in ["top", "bottom"] {
                let panel = MenuPanelView()
                panel.updateToken(snapshot, notifySize: false)
                panel.select(tab: .token)
                panel.tokenPane.applyStateForSnapshot(range: range, hourScope: .today, trendMode: .stack)
                panel.tokenPane.openDetailForSnapshot(.cache)
                let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                MenuPanelSnapshot.render(
                    view: panel, size: size, appearanceName: .aqua,
                    to: directory.appendingPathComponent("menu-token-cache-\(slug)-\(suffix).png"),
                    postLayout: { view in
                        guard let panel = view as? MenuPanelView, suffix == "bottom" else { return }
                        panel.tokenPane.detailPane.scrollToBottomForSnapshot()
                    })
            }
            lines.append(contentsOf: cacheMetricsLines(snapshot: snapshot, range: range, slug: slug))
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-cache-metrics.txt"),
                        atomically: true, encoding: .utf8)
        AppContext.shared.logger.info("缓存命中二级页取证完成（三档范围 × 顶部/底部 + 数值台账）")
    }

    /// 单档范围的台账：主数值 / 桶数 / 走势区间 / 上一周期 / 差值 / 样本量 / 面包屑与说明卡
    private static func cacheMetricsLines(snapshot: HarnessUsageSnapshot,
                                          range: TokenRange,
                                          slug: String) -> [String] {
        let panel = MenuPanelView()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.tokenPane.applyStateForSnapshot(range: range, hourScope: .today, trendMode: .stack)
        panel.tokenPane.openDetailForSnapshot(.cache)
        panel.layoutSubtreeIfNeeded()
        let detail = panel.tokenPane.detailPane
        let scroll = detail.snapshotScrollMetrics()
        // 页面实际渲染出来的模型（与视图同一份派生，避免台账自成一套）
        guard let model = panel.tokenPane.lastModel else {
            return ["# \(slug): 无模型（快照为空）"]
        }
        let page = model.cachePage
        let crumb = detail.crumbLabel.stringValue
        let meta = detail.metaLabel.stringValue
        var lines: [String] = []
        lines.append("# \(slug) 面包屑 [" + crumb + "] meta [" + meta + "]")
        lines.append("\(slug).hero: value=\(page.heroValue) unit=[\(page.heroUnit)]")
        lines.append("\(slug).heroSub: [\(page.heroSub)]")
        lines.append("\(slug).buckets: count=\(page.bucketCount) unit=[\(page.bucketUnitText)]"
            + " series=\(page.series.count) axis=\(page.axisLabels.count)")
        lines.append("\(slug).trend: title=[\(page.trendTitle)] meta=[\(page.trendMeta)]")
        lines.append("\(slug).ring: fraction=\(String(format: "%.4f", page.ringFraction))"
            + " text=\(page.ringText) a11y=[\(page.ringAccessibility)]")
        lines.append("\(slug).ringKeys: 缓存读=[\(page.cacheReadText)] 未缓存输入=[\(page.uncachedText)]"
            + " \(page.saveRatioLabel)=[\(page.saveRatioText)] 输出=[\(page.outputText)]")
        lines.append("\(slug).compare: title=[\(page.compareTitle)] meta=[\(page.compareMeta)]"
            + " \(page.currentLabel)=\(page.currentRateText)(cache \(page.currentCacheText))"
            + " / \(page.previousLabel)=\(page.previousRateText)(cache \(page.previousCacheText))")
        lines.append("\(slug).stat: \(page.currentLabel)命中=\(page.currentRateText)"
            + " \(page.previousLabel)命中=\(page.previousRateText)"
            + " \(page.deltaLabel)=\(page.deltaText) 样本量=[\(page.sampleText)]"
            + " hasPrevious=\(page.hasPrevious ? "YES" : "NO")")
        lines.append("\(slug).note: [\(page.note)]")
        lines.append(String(format: "%@.scroll: document=%.1f viewport=%.1f scrollable=%@",
                            slug, scroll.document, scroll.viewport,
                            scroll.document > scroll.viewport + 0.5 ? "YES" : "NO"))
        return lines
    }

    /// 文件名后缀：today / d7 / d30
    private static func cacheSlug(_ range: TokenRange) -> String {
        switch range {
        case .today: return "today"
        case .d7: return "d7"
        case .d30: return "d30"
        }
    }
}
#endif
