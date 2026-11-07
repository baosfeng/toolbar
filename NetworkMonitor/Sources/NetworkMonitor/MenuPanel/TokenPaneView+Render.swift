import AppKit
import NetworkMonitorCore

// MARK: - Token 页渲染（TokenPaneView 扩展）

/// 主面板逐块渲染 —— 从 TokenPaneView.swift 拆出（单文件体积门禁）
///
/// 所有数值都来自 TokenPaneModel（派生计算在 TokenDerive），这里只做「模型 → 控件」的搬运，
/// 不在视图层重算占比 / 窗口 / 环比，保证同一份数据在各区块口径一致。
extension TokenPaneView {

    func render() {
        guard let snapshot else { return }
        let model = TokenPaneModel.make(snapshot: snapshot,
                                        range: range,
                                        hourScope: hourScope,
                                        hourView: hourView,
                                        metric: metric,
                                        trendMode: trendMode)
        lastModel = model

        hostLabel.stringValue = model.hostLabel
        heroView.update(hero: model.hero)
        rangeControl.select(range.rawValue, notify: false)

        for (index, card) in familyCards.enumerated() where index < model.cards.count {
            card.update(card: model.cards[index])
        }

        daySegment.isHidden = range != .today
        viewAction.isHidden = range == .d30
        daySegment.select(hourScope.rawValue, notify: false)
        viewAction.update(title: "切：" + (hourView == .stack ? "对比" : "堆叠"))
        hourTitle.stringValue = model.bucketTitle
        hourMeta.stringValue = model.bucketMeta
        hourAction.update(title: "切：" + (metric == .total ? "请求数" : "总量"))

        // 对比态只在今日/近 7 天成立（近 30 天没有对照窗口），与 Core 的 bucketLegend 口径同条件
        let comparing = hourView == .compare && range != .d30
        let shape: TokenBarsView.Shape
        if comparing {
            shape = .pair
        } else {
            shape = metric == .request ? .request : .stack
        }
        hourBars.update(buckets: model.buckets,
                        previous: model.prevBuckets,
                        cumulative: model.cumulative,
                        shape: shape,
                        showsCumulative: shape == .stack,
                        pairMetric: metric == .request ? .request : .output,
                        accessibility: model.bucketTitle + "，每根柱可点开该时段详情")
        hourAxis.update(labels: axisLabels(for: model))
        hourLegend.update(items: legendItems(for: model, comparing: comparing,
                                             lineColor: hourBars.lineColor))

        trendTitle.stringValue = model.trendTitle
        trendMeta.stringValue = model.trendMeta
        trendAction.update(title: "切：" + (trendMode == .stack ? "分线" : "面积"))
        let trendValues = trendMode == .stack
            ? model.trendBuckets.map { Double($0.total) }
            : model.trendBuckets.map { Double($0.cache) }
        trendSpark.update(values: trendValues, accessibility: "近 14 天每日 Token 总量走势")

        cacheMeta.stringValue = model.hitMeta
        cacheRing.update(rate: model.hitRateFraction,
                         text: model.hitText,
                         accessibility: "缓存命中率 " + model.hitText + "%")
        cacheLegend.update(items: [
            TokenLegendItem(color: TokenPaneStyle.cacheColor, title: "缓存读", value: model.cacheReadText),
            TokenLegendItem(color: TokenPaneStyle.uncachedColor, title: "未缓存", value: model.uncachedText),
            TokenLegendItem(color: nil, title: model.hitBucketText, value: "", dashed: true),
        ])

        projectMeta.stringValue = model.projectMeta
        modelMeta.stringValue = model.modelMeta
        // 占比条只有色块、图例又会被 296pt 宽截断：整条 toolTip 逐段给出「provider/model 金额 · 占比」
        let projectBarRows = Array(model.projects.prefix(6))
        let modelBarRows = Array(model.models.prefix(6))
        projectBar.update(shares: projectBarRows.map { $0.share },
                          colors: projectBarRows.map { TokenPaneStyle.distroColor($0.colorIndex) },
                          accessibility: "按项目累计占比条",
                          tip: TokenDerive.stackBarTip(projectBarRows,
                                                       hiddenCount: model.projects.count - projectBarRows.count))
        modelBar.update(shares: modelBarRows.map { $0.share },
                        colors: modelBarRows.map { TokenPaneStyle.distroColor($0.colorIndex + 1) },
                        accessibility: "按模型累计占比条",
                        tip: TokenDerive.stackBarTip(modelBarRows,
                                                     hiddenCount: model.models.count - modelBarRows.count))
        updateDistroRows(projectRows, model.projects)
        updateDistroRows(modelRows, model.models)

        if let compare = model.compare {
            compareCard.isHidden = false
            compareTotal.stringValue = "总 tok " + compare.currentText
            compareDelta.stringValue = compare.deltaText
            compareDelta.textColor = compare.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk
            compareCurrentRow.update(name: compare.currentLabel, text: compare.currentText,
                                     fraction: compare.currentFraction, color: TokenPaneStyle.uncachedColor)
            comparePreviousRow.update(name: compare.previousLabel, text: compare.previousText,
                                      fraction: compare.previousFraction, color: TokenPaneStyle.ghostColor)
        } else {
            compareCard.isHidden = true
        }

        stateBand.update(items: model.stateBand)

        if let detailKind {
            detailPane.update(kind: detailKind, model: model, snapshot: snapshot,
                              selection: selection, hourScope: hourScope)
            syncDistroHoverTips(kind: detailKind, model: model)
        }
        onContentChanged?()
    }

    /// 二级页「按项目 / 按模型」的占比条与图例：挂上 Core 生成的悬停文案
    ///
    /// 这两页的构建代码在 TokenDetailPages+Distro.swift（另一任务在改口径文案），
    /// 所以文案挂载单独收在这里：打开二级页与每次重渲染都调用同一份，不重不漏。
    func syncDistroHoverTips(kind: TokenDetailKind, model: TokenPaneModel) {
        guard kind == .projects || kind == .models else { return }
        let rows = kind == .projects ? model.projects : model.models
        detailPane.applyDistroHoverTips(barTip: TokenDerive.stackBarTip(rows),
                                        legendTips: rows.prefix(3).map { TokenDerive.stackBarTip([$0]) })
    }

    // MARK: - 坐标轴与图例

    /// 坐标轴标签：按桶数稀释（7→逐格，24→每隔 4，30→每隔 6）
    private func axisLabels(for model: TokenPaneModel) -> [String] {
        let count = model.buckets.count
        guard count > 0 else { return [] }
        let step: Int
        if count <= 7 { step = 1 } else if count <= 12 { step = 2 } else if count <= 24 { step = 4 } else { step = 6 }
        return model.buckets.enumerated().map { index, bucket in
            let short = bucket.label.replacingOccurrences(of: "时", with: "")
            return (index % step == 0 || index == count - 1) ? short : ""
        }
    }

    /// 图例：项数与当前形态一致，取色 / 线型与图上的画法同源
    ///
    /// - 对比态：两项（本周期实线 + 对照虚线），不再套三段堆叠色；
    /// - 请求数态：柱只有 requestColor 一种色，第二项是昨日对照数（虚线色块）；
    /// - 堆叠态：缓存读 / 未缓存 / 输出三条实体项——字号提到 10pt 后第四项（累计基准）
    ///   会把 296pt 宽度撑破，而「累计 776M」已在卡头 meta 里，虚线本身照画，信息不减。
    private func legendItems(for model: TokenPaneModel, comparing: Bool,
                             lineColor: NSColor) -> [TokenLegendItem] {
        if comparing {
            return model.bucketLegend.prefix(2).enumerated().map { index, item in
                index == 0
                    ? TokenLegendItem(color: lineColor, title: item.title, value: item.value)
                    : TokenLegendItem(color: TokenPaneStyle.ghostColor, title: item.title,
                                      value: item.value, dashed: true)
            }
        }
        if metric == .request {
            return model.bucketLegend.enumerated().map { index, item in
                index == 0
                    ? TokenLegendItem(color: TokenPaneStyle.requestColor, title: item.title, value: item.value)
                    : TokenLegendItem(color: TokenPaneStyle.ghostColor, title: item.title,
                                      value: item.value, dashed: true)
            }
        }
        let palette: [NSColor] = [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor,
                                  TokenPaneStyle.outputColor]
        return model.bucketLegend.prefix(palette.count).enumerated().map { index, item in
            TokenLegendItem(color: palette[index], title: item.title, value: item.value)
        }
    }

    private func updateDistroRows(_ rows: [TokenDistroRowView], _ data: [TokenDistroRow]) {
        for (index, view) in rows.enumerated() {
            if index < data.count {
                view.isHidden = false
                view.update(row: data[index], showsProvider: false)
            } else {
                view.isHidden = true
            }
        }
    }
}
// MARK: - 二级页分布悬停文案挂载

extension TokenDetailPaneView {

    /// 给「按项目 / 按模型」页的顶部占比条与图例项挂上悬停文案
    ///
    /// 这两页的构建代码在 TokenDetailPages+Distro.swift，调用点若直接改那里会与「口径文案」任务撞车，
    /// 所以挂载集中在本文件：渲染完成后按类型遍历一次子树，把 Core 生成的文案挂到第一个占比条与图例行上。
    /// - Parameters:
    ///   - barTip: 整条占比条文案（逐段「provider/model 金额 · 占比」，换行分隔）
    ///   - legendTips: 图例前三项的逐项文案（与图例项顺序一致）
    func applyDistroHoverTips(barTip: String, legendTips: [String]) {
        var bars: [TokenStackBarView] = []
        var legends: [TokenLegendRowView] = []
        func walk(_ node: NSView) {
            if let bar = node as? TokenStackBarView { bars.append(bar) }
            if let legend = node as? TokenLegendRowView { legends.append(legend) }
            for subview in node.subviews { walk(subview) }
        }
        walk(self)
        if let bar = bars.first {
            bar.toolTip = barTip.isEmpty ? nil : barTip
        }
        // 图例行此刻已由构建代码填好前三项：逐项补 tip（项数不同时按较短的一边对齐，不越界）
        guard let legend = legends.first else { return }
        legend.applyItemTips(legendTips)
    }
}
