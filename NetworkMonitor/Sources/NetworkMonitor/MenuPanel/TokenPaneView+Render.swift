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

        let shape: TokenBarsView.Shape
        if hourView == .compare, range != .d30 {
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
        hourLegend.update(items: legendItems(for: model))

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
            (color: Optional(TokenPaneStyle.cacheColor), title: "缓存读", value: model.cacheReadText),
            (color: Optional(TokenPaneStyle.uncachedColor), title: "未缓存", value: model.uncachedText),
            (color: nil, title: model.hitBucketText, value: ""),
        ])

        projectMeta.stringValue = model.projectMeta
        modelMeta.stringValue = model.modelMeta
        projectBar.update(shares: model.projects.prefix(6).map { $0.share },
                          colors: model.projects.prefix(6).map { TokenPaneStyle.distroColor($0.colorIndex) },
                          accessibility: "按项目累计占比条")
        modelBar.update(shares: model.models.prefix(6).map { $0.share },
                        colors: model.models.prefix(6).map { TokenPaneStyle.distroColor($0.colorIndex + 1) },
                        accessibility: "按模型累计占比条")
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
        }
        onContentChanged?()
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

    /// 图例：只保留三条实体项
    ///
    /// 字号提到 10pt 后第四项（累计基准）会把 296pt 宽度撑破，而「累计 776M」已在卡头 meta 里，
    /// 虚线本身照画（showsCumulative），信息不减。
    private func legendItems(for model: TokenPaneModel) -> [(color: NSColor?, title: String, value: String)] {
        let palette: [NSColor] = [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor,
                                  TokenPaneStyle.outputColor]
        return model.bucketLegend.prefix(palette.count).enumerated().map { index, item in
            (color: palette[index], title: item.title, value: item.value)
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
