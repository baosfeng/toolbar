import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - 缓存命中二级页（原独立第 3 屏，两屏收敛后降级为面板内二级页）

/// 缓存命中页的内容构建 —— 从 TokenDetailPages+Charts.swift 拆出。
///
/// 为什么单独一个文件而不是继续挂 +Charts：它不是一个「图表页」，
/// 而是**一整个屏的东西降级成页**（环 / 走势 / 对照 / 统计 / 口径），
/// 与按小时、单桶、天趋势三页平级。三页按「图表 vs 单桶」划分，
/// 这一页按「缓存口径」划分，混在一起会让 TokenDetailPages 族越堆越大。
extension TokenDetailPaneView {

    // MARK: 缓存命中（原独立第 3 屏，两屏收敛后降级到这里）

    /// 缓存命中页：大环 + 四行拆分 / 命中率走势 / 本周期 vs 上一周期 / 样本统计 + 口径说明
    ///
    /// 全部数值取 Core 的 TokenCachePage（与总览屏那条命中率同源），视图只搬运不重算。
    /// 存在理由：改前它是主面板一整屏，但一个比率摊满 409pt 只填到 350pt，
    /// 还要额外占一条切换段落；降级为二级页后主面板只需一条可点的命中率条。
    func buildCache(model: TokenPaneModel) -> [NSView] {
        let page = model.cachePage
        overrideCrumb("/ 缓存命中", meta: page.rangeTitle + " · " + page.bucketUnitText)

        let ring = TokenRingView(size: PaneCardStyle.bigRingSize,
                                 lineWidth: PaneCardStyle.bigRingWidth)
        ring.update(rate: page.ringFraction, text: page.ringText, accessibility: page.ringAccessibility)
        let keyRows = [
            TokenContentKit.keyRow("缓存读", page.cacheReadText, color: TokenPaneStyle.cacheInk),
            TokenContentKit.keyRow("未缓存输入", page.uncachedText),
            TokenContentKit.keyRow(page.saveRatioLabel, page.saveRatioText),
            TokenContentKit.keyRow("输出", page.outputText),
        ]
        let column = NSStackView(views: keyRows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        for row in keyRows { row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        column.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        let ringRow = NSStackView(views: [ring, column])
        ringRow.orientation = .horizontal
        ringRow.alignment = .centerY
        ringRow.spacing = 12
        let ringCard = TokenBoxView()
        ringCard.setRows([TokenContentKit.head("缓存命中率", meta: page.rangeTitle + " · " + page.bucketUnitText),
                          ringRow])

        let trendSpark = TokenSparkView(height: 56, stroke: TokenPaneStyle.cacheColor,
                                        fill: TokenPaneStyle.cacheColor)
        trendSpark.update(points: page.series, accessibility: page.trendAccessibility,
                          baseline: page.seriesFloor)
        let trendCard = TokenBoxView()
        trendCard.setRows([TokenContentKit.head(page.trendTitle, meta: page.trendMeta),
                           trendSpark,
                           TokenContentKit.axisView(page.axisLabels)])

        let compareCurrent = TokenCompareRowView()
        compareCurrent.update(name: page.currentLabel, text: page.currentRateText,
                              fraction: page.currentFraction, color: TokenPaneStyle.cacheColor)
        let comparePrevious = TokenCompareRowView()
        comparePrevious.update(name: page.previousLabel, text: page.previousRateText,
                               fraction: page.hasPrevious ? page.previousFraction : 0,
                               color: TokenPaneStyle.ghostColor)
        let compareCard = TokenBoxView()
        compareCard.setRows([TokenContentKit.head(page.compareTitle, meta: page.compareMeta),
                             compareCurrent, comparePrevious])

        let statsCard = TokenBoxView()
        statsCard.setRows([TokenContentKit.twoColumn([
            TokenContentKit.keyRow(page.currentLabel + "命中", page.currentRateText),
            TokenContentKit.keyRow(page.previousLabel + "命中", page.previousRateText),
            TokenContentKit.keyRow(page.deltaLabel, page.deltaText,
                   color: page.hasPrevious ? (page.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk)
                                           : TokenPaneStyle.secondaryText),
            TokenContentKit.keyRow("样本量", page.sampleText),
        ])])

        return [ringCard, trendCard, compareCard, statsCard, TokenContentKit.note(page.note)]
    }
}