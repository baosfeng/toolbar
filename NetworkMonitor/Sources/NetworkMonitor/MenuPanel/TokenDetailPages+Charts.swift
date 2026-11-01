import AppKit
import NetworkMonitorCore

// MARK: - 二级页：按小时 / 单桶 / 天趋势

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
                        accessibility: "今日与昨日同时段请求数对比柱")
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

    // MARK: 单桶详情（某小时 / 某一天）

    func buildBucket(model: TokenPaneModel,
                     snapshot: HarnessUsageSnapshot,
                     selection: TokenBucketSelection?) -> [NSView] {
        let index = selection?.index ?? 0
        let isHour = selection?.isHour ?? true

        if isHour {
            let scope = selection?.scope ?? .today
            let buckets = scope == .today ? TokenDerive.todayBuckets(snapshot) : TokenDerive.yesterdayBuckets(snapshot)
            let other = scope == .today ? TokenDerive.yesterdayBuckets(snapshot) : TokenDerive.todayBuckets(snapshot)
            return hourBucketRows(index: index, scope: scope, buckets: buckets, other: other)
        }

        let buckets = TokenDerive.dailyBuckets(snapshot, days: max(model.range.days, 2))
        let other = TokenDerive.previousDailyBuckets(snapshot, days: max(model.range.days, 2))
        return dayBucketRows(index: index, range: model.range, buckets: buckets, other: other)
    }

    private func hourBucketRows(index: Int,
                                scope: TokenHourScope,
                                buckets: [TokenBucket],
                                other: [TokenBucket]) -> [NSView] {
        let current = buckets[safe: index] ?? .empty
        let before = other[safe: index] ?? .empty
        let dayTotal = TokenDerive.sum(buckets).total
        let share = dayTotal > 0 ? Double(current.total) / Double(dayTotal) : 0
        let ranking = buckets.filter { $0.total > current.total }.count + 1
        let tokenDelta = TokenFormatting.delta(current: current.total, previous: before.total)?.text ?? "—"
        let requestDelta = TokenFormatting.delta(current: current.request, previous: before.request)?.text ?? "—"
        overrideCrumb("/ 按小时 · \(index) 时", meta: scope.title + " · 24 桶")

        let split = TokenStackBarView(height: 6)
        split.update(shares: splitShares(current),
                     colors: [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor, TokenPaneStyle.outputColor],
                     accessibility: "第 \(index) 时三段拆分")
        let splitCard = TokenBoxView()
        splitCard.setRows([
            head("三段拆分 · \(index) 时", meta: "占" + scope.title + "全天 "
                + TokenFormatting.percent(share)),
            split,
            twoColumn([
                keyRow("缓存读", TokenFormatting.tokens(current.cache), color: TokenPaneStyle.cacheInk),
                keyRow("未缓存", TokenFormatting.tokens(current.uncached), color: TokenPaneStyle.uncachedInk),
                keyRow("输出", TokenFormatting.tokens(current.output)),
                keyRow("请求数", TokenFormatting.grouped(current.request), color: TokenPaneStyle.requestInk),
            ]),
        ])

        let scale = Double(max(current.total, before.total, 1))
        let compareCard = TokenBoxView()
        compareCard.setRows([
            head(scope.title + " \(index) 时 · vs " + scope.otherTitle + "同时段", meta: "总量 " + tokenDelta),
            compareRow(name: scope.title + " tok", text: TokenFormatting.tokens(current.total),
                       fraction: Double(current.total) / scale, color: TokenPaneStyle.uncachedColor),
            compareRow(name: scope.otherTitle + " tok", text: TokenFormatting.tokens(before.total),
                       fraction: Double(before.total) / scale, color: TokenPaneStyle.ghostColor),
            compareRow(name: scope.title + " 请求", text: TokenFormatting.grouped(current.request),
                       fraction: Double(current.request) / Double(max(current.request, before.request, 1)),
                       color: TokenPaneStyle.requestColor),
            compareRow(name: scope.otherTitle + " 请求", text: TokenFormatting.grouped(before.request),
                       fraction: Double(before.request) / Double(max(current.request, before.request, 1)),
                       color: TokenPaneStyle.ghostColor),
        ])

        let extraCard = TokenBoxView()
        extraCard.setRows([
            twoColumn([
                keyRow("占" + scope.title + "全天", TokenFormatting.percent(share)),
                keyRow("24 桶排名", "\(ranking) / \(buckets.count)"),
                keyRow("较同时段总量", tokenDelta),
                keyRow("较同时段请求", requestDelta),
            ]),
        ])

        return [hero(TokenFormatting.tokens(current.total), unit: "tok / 时",
                     sub: scope.title + " \(index):00–\(index):59 · 三段相加 = 该小时总 tok"),
                splitCard, compareCard, extraCard,
                note("口径：按小时桶仅「今日」与「昨日」可得；历史日只有天粒度，所以 7 / 30 天那排柱点开的是日详情。三段相加 = 该小时总 tok，请求数与 tok 不同源，不做除法换算。")]
    }

    private func dayBucketRows(index: Int,
                               range: TokenRange,
                               buckets: [TokenBucket],
                               other: [TokenBucket]) -> [NSView] {
        let current = buckets[safe: index] ?? .empty
        let before = other[safe: index] ?? .empty
        let windowTotal = TokenDerive.sum(buckets).total
        let share = windowTotal > 0 ? Double(current.total) / Double(windowTotal) : 0
        let ranking = buckets.filter { $0.total > current.total }.count + 1
        let tokenDelta = TokenFormatting.delta(current: current.total, previous: before.total)?.text ?? "—"
        let requestDelta = TokenFormatting.delta(current: current.request, previous: before.request)?.text ?? "—"
        overrideCrumb("/ 按天 · " + current.label, meta: range.title + " · 天粒度")

        let split = TokenStackBarView(height: 6)
        split.update(shares: splitShares(current),
                     colors: [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor, TokenPaneStyle.outputColor],
                     accessibility: current.label + " 三段拆分")
        let splitCard = TokenBoxView()
        splitCard.setRows([
            head("三段拆分 · 日汇总", meta: "占" + range.title + " " + TokenFormatting.percent(share)),
            split,
            twoColumn([
                keyRow("缓存读", TokenFormatting.tokens(current.cache), color: TokenPaneStyle.cacheInk),
                keyRow("未缓存", TokenFormatting.tokens(current.uncached), color: TokenPaneStyle.uncachedInk),
                keyRow("输出", TokenFormatting.tokens(current.output)),
                keyRow("请求数", TokenFormatting.grouped(current.request), color: TokenPaneStyle.requestInk),
            ]),
        ])

        let scale = Double(max(current.total, before.total, 1))
        let compareCard = TokenBoxView()
        compareCard.setRows([
            head("vs 前一日", meta: "总量 " + tokenDelta),
            compareRow(name: "该日 tok", text: TokenFormatting.tokens(current.total),
                       fraction: Double(current.total) / scale, color: TokenPaneStyle.uncachedColor),
            compareRow(name: "前一日 tok", text: TokenFormatting.tokens(before.total),
                       fraction: Double(before.total) / scale, color: TokenPaneStyle.ghostColor),
            compareRow(name: "该日 请求", text: TokenFormatting.grouped(current.request),
                       fraction: Double(current.request) / Double(max(current.request, before.request, 1)),
                       color: TokenPaneStyle.requestColor),
            compareRow(name: "前一日 请求", text: TokenFormatting.grouped(before.request),
                       fraction: Double(before.request) / Double(max(current.request, before.request, 1)),
                       color: TokenPaneStyle.ghostColor),
        ])

        let extraCard = TokenBoxView()
        extraCard.setRows([
            twoColumn([
                keyRow("占窗口", TokenFormatting.percent(share)),
                keyRow("窗口内排名", "\(ranking) / \(buckets.count)"),
                keyRow("较前一日总量", tokenDelta),
                keyRow("较前一日请求", requestDelta),
            ]),
        ])

        return [hero(TokenFormatting.tokens(current.total), unit: "tok / 日",
                     sub: current.label + " · 日汇总 · 与前一日对比（仅天粒度）"),
                splitCard, compareCard, extraCard,
                note("口径：历史日仅天粒度——小时拆分只有今日与昨日可得，所以本页只给日汇总 + 与前一日对比，不画小时柱。项目与模型仍是累计口径，不随窗口变化。")]
    }

    private func compareRow(name: String, text: String, fraction: Double, color: NSColor) -> NSView {
        let row = TokenCompareRowView()
        row.update(name: name, text: text, fraction: fraction, color: color)
        return row
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
