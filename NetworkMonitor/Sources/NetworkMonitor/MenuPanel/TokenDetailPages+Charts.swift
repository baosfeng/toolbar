import AppKit
import NetworkMonitorCore

// MARK: - 二级页：按小时 / 单桶 / 天趋势
//
// 单桶详情页（某小时 / 某一天）见 TokenDetailPages+Buckets.swift。

extension TokenDetailPaneView {

    // MARK: 按小时三段拆分

    func buildHourly(snapshot: HarnessUsageSnapshot, hourScope: TokenHourScope) -> [NSView] {
        let buckets = hourScope == .today ? TokenDerive.todayBuckets(snapshot) : TokenDerive.yesterdayBuckets(snapshot)
        let other = hourScope == .today ? TokenDerive.yesterdayBuckets(snapshot) : TokenDerive.todayBuckets(snapshot)
        let total = TokenDerive.sum(buckets)
        let peak = TokenDerive.peakBucket(buckets)
        overrideCrumb("/ 按小时 · 三段拆分", meta: "00–23 时")

        let bars = TokenBarsView()
        bars.onSelect = { [weak self] index in
            self?.onSelectBucket?(TokenBucketSelection(index: index, isHour: true, scope: hourScope))
        }
        // 三段堆叠按「当日最大单桶总量」归一，否则柱高会溢出卡片
        bars.update(buckets: buckets, shape: .stack, showsCumulative: false,
                    scaleMax: buckets.map { $0.total }.max() ?? 1,
                    accessibility: hourScope.title + " 24 小时三段堆叠柱，每根柱可点开该小时详情")
        bars.heightAnchor.constraint(equalToConstant: TokenPaneStyle.detailChartHeight).isActive = true

        let chartCard = TokenBoxView()
        chartCard.setRows([
            head(hourScope.title + " 24 小时", meta: "峰值 " + TokenFormatting.tokens(peak.bucket.total)),
            bars,
            axisView(buckets.map { $0.label }),
            twoColumn([
                keyRow("缓存读", TokenFormatting.tokens(total.cache), color: TokenPaneStyle.cacheInk),
                keyRow("未缓存", TokenFormatting.tokens(total.uncached), color: TokenPaneStyle.uncachedInk),
                keyRow("输出", TokenFormatting.tokens(total.output)),
                keyRow("请求", TokenFormatting.grouped(total.request), color: TokenPaneStyle.requestInk),
            ]),
        ])

        let pairBars = TokenBarsView()
        pairBars.onSelect = { [weak self] index in
            self?.onSelectBucket?(TokenBucketSelection(index: index, isHour: true, scope: hourScope))
        }
        pairBars.update(buckets: buckets, previous: other, shape: .pair, showsCumulative: false,
                        scaleMax: max(buckets.map { $0.request }.max() ?? 0,
                                      other.map { $0.request }.max() ?? 0),
                        accessibility: "今日与昨日同时段请求数对比折线（实线今日、虚线昨日）")
        pairBars.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let pairCard = TokenBoxView()
        pairCard.setRows([
            head("今日 / 昨日 · 请求数",
                 meta: "今日 " + TokenFormatting.grouped(TokenDerive.sum(TokenDerive.todayBuckets(snapshot)).request)
                     + " / 昨日 " + TokenFormatting.grouped(TokenDerive.sum(TokenDerive.yesterdayBuckets(snapshot)).request)),
            pairBars,
        ])

        let statCard = TokenBoxView()
        statCard.setRows([
            twoColumn([
                keyRow("峰值时段", "\(peak.index) 时"),
                keyRow("峰值 tok/h", TokenFormatting.tokens(peak.bucket.total)),
                keyRow("均值 tok/h", TokenFormatting.tokens(total.total / 24)),
                keyRow("缓存占比", TokenFormatting.percent(TokenDerive.hitRate(total)), color: TokenPaneStyle.cacheInk),
            ]),
        ])

        return [hero(TokenFormatting.tokens(total.total), unit: "tok",
                     sub: hourScope.title + " 24 桶 · 缓存读 / 未缓存输入 / 输出 · 昨日同时段可对比"),
                chartCard, pairCard, statCard,
                note("口径：按小时桶仅「今日」可得（昨日同时段真算同比）；历史日只有天粒度。三段相加 = 当日总 tok，请求数与 tok 不同源，不做除法换算。")]
    }

    // MARK: 天趋势

    func buildTrend(snapshot: HarnessUsageSnapshot) -> [NSView] {
        let buckets = TokenDerive.dailyBuckets(snapshot, days: 30)
        let totals = buckets.map { Double($0.total) }
        let total = TokenDerive.sum(buckets).total
        let peak = totals.max() ?? 0
        let low = totals.min() ?? 0
        let average = total / max(buckets.count, 1)
        let days = buckets.filter { $0.total > 0 }.count
        overrideCrumb("/ 天趋势", meta: "上限 33 天")

        let chart = TokenSparkView(height: 64, stroke: TokenPaneStyle.uncachedColor,
                                   fill: TokenPaneStyle.uncachedColor)
        chart.update(values: totals, accessibility: "近 30 天每日 Token 总量走势")

        let chartCard = TokenBoxView()
        chartCard.setRows([
            head("每日总 tok", meta: "峰 " + TokenFormatting.tokens(Int(peak))),
            chart,
            axisView(["30 天前", "23 天前", "16 天前", "9 天前", "今日"]),
        ])

        let ranking: [NSView] = buckets.enumerated()
            .sorted { $0.element.total > $1.element.total }
            .prefix(5)
            .map { pair in
                let label = pair.offset == buckets.count - 1
                    ? "今日"
                    : "\(buckets.count - 1 - pair.offset) 天前"
                return keyRow(label, TokenFormatting.tokens(pair.element.total))
            }
        let topCard = TokenBoxView()
        topCard.setRows([head("日总量 Top 5", meta: "tok")] + ranking)

        let statCard = TokenBoxView()
        statCard.setRows([
            twoColumn([
                keyRow("日均", TokenFormatting.tokens(average)),
                keyRow("最高", TokenFormatting.tokens(Int(peak))),
                keyRow("最低", TokenFormatting.tokens(Int(low))),
                keyRow("有记录天数", "\(days) / \(buckets.count)"),
            ]),
        ])

        return [hero(TokenFormatting.tokens(total), unit: "tok / 30 天",
                     sub: "按天序列 · 索引里能取到的最长 30 天 · 今日那根 = 主面板今日总量"),
                chartCard, topCard, statCard,
                note("口径：天粒度序列在索引里最多回溯 33 天，本页固定取最近 30 天。「今日」那根柱 = 主面板今日总量。不给跨设备合计。")]
    }
}
