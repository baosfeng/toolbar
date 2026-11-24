#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 缓存命中二级页三档范围台账（仅 DEBUG）

/// 为什么单独取证：缓存这块此前是「主数值今日 / 走势与均值 30 天 / 逐桶今日 24 桶」的混合口径，
/// 用户要求「我选择 7 天就只展示 7 天的」。三档范围各跑一遍、把数值与文案逐项落到台账，
/// 才能证明「换范围真的换了数据」而不是换了个标题。
///
/// **截图不在这里**：页面滚动截图由 +Details 的四张二级页取证统一负责（含 cache 页），
/// 这里只出范围矩阵的数值台账——同一件事画两遍图是重复取证。
@MainActor
extension TokenPaneSnapshot {

    /// 三档范围 × 缓存二级页：数值与文案台账
    static func captureCacheScreen(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for range in TokenRange.allCases {
            lines.append(contentsOf: cacheMetricsLines(snapshot: snapshot, range: range,
                                                       slug: cacheSlug(range)))
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-cache-metrics.txt"),
                        atomically: true, encoding: .utf8)
        AppContext.shared.logger.info("缓存命中二级页台账完成（三档范围 + 数值文案）")
    }

    // MARK: - 内部

    /// 选好范围并打开缓存二级页的面板（台账与 +Details 的截图共用同一条链路）
    private static func makeCachePanel(snapshot: HarnessUsageSnapshot, range: TokenRange) -> MenuPanelView {
        let panel = tokenPanel(snapshot)
        panel.tokenPane.applyStateForSnapshot(range: range, hourScope: .today)
        panel.tokenPane.openDetailForSnapshot(.cache)
        return panel
    }

    /// 单档范围的台账：主数值 / 桶数 / 走势区间 / 上一周期 / 差值 / 样本量 / 口径
    private static func cacheMetricsLines(snapshot: HarnessUsageSnapshot,
                                          range: TokenRange,
                                          slug: String) -> [String] {
        let panel = makeCachePanel(snapshot: snapshot, range: range)
        panel.layoutSubtreeIfNeeded()
        // 页面实际渲染出来的模型（与视图同一份派生，避免台账自成一套）
        guard let model = panel.tokenPane.lastModel else {
            return ["# \(slug): 无模型（快照为空）"]
        }
        let page = model.cachePage
        let scroll = panel.tokenPane.detailPane.snapshotScrollMetrics()
        return [
            "# \(slug) 缓存二级页 · crumb=" + TokenDetailKind.cache.crumb,
            "\(slug).hero: value=\(page.heroValue) unit=[\(page.heroUnit)]",
            "\(slug).heroSub: [\(page.heroSub)]",
            "\(slug).buckets: count=\(page.bucketCount) unit=[\(page.bucketUnitText)] series=\(page.series.count) axis=\(page.axisLabels.count)",
            "\(slug).trend: title=[\(page.trendTitle)] meta=[\(page.trendMeta)]",
            "\(slug).ring: fraction=\(String(format: "%.4f", page.ringFraction)) text=\(page.ringText) a11y=[\(page.ringAccessibility)]",
            "\(slug).ringKeys: 缓存读=[\(page.cacheReadText)] 未缓存输入=[\(page.uncachedText)] \(page.saveRatioLabel)=[\(page.saveRatioText)] 输出=[\(page.outputText)]",
            "\(slug).compare: title=[\(page.compareTitle)] meta=[\(page.compareMeta)] \(page.currentLabel)=\(page.currentRateText) / \(page.previousLabel)=\(page.previousRateText)",
            "\(slug).stat: \(page.deltaLabel)=\(page.deltaText) 样本量=[\(page.sampleText)] hasPrevious=\(page.hasPrevious ? "YES" : "NO")",
            "\(slug).note: [\(page.note)]",
            String(format: "%@.scroll: document=%.1f viewport=%.1f scrollable=%@",
                   slug, scroll.document, scroll.viewport,
                   scroll.document > scroll.viewport + 0.5 ? "YES" : "NO"),
        ]
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
