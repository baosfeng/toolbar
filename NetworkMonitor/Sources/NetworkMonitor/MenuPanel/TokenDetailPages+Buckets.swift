import AppKit
import NetworkMonitorCore

// MARK: - 二级页：单桶详情（某小时 / 某一天）

extension TokenDetailPaneView {

    /// 单桶详情页：小时桶走 hourBucketRows，历史日走 dayBucketRows
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
        split.update(shares: TokenContentKit.splitShares(current),
                     colors: [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor, TokenPaneStyle.outputColor],
                     accessibility: "第 \(index) 时三段拆分")
        let splitCard = TokenBoxView()
        splitCard.setRows([
            TokenContentKit.head("三段拆分 · \(index) 时", meta: "占" + scope.title + "全天 "
                + TokenFormatting.percent(share)),
            split,
            TokenContentKit.twoColumn([
                TokenContentKit.keyRow("缓存读", TokenFormatting.tokens(current.cache), color: TokenPaneStyle.cacheInk),
                TokenContentKit.keyRow("未缓存", TokenFormatting.tokens(current.uncached), color: TokenPaneStyle.uncachedInk),
                TokenContentKit.keyRow("输出", TokenFormatting.tokens(current.output)),
                TokenContentKit.keyRow("请求数", TokenFormatting.grouped(current.request), color: TokenPaneStyle.requestInk),
            ]),
        ])

        let scale = Double(max(current.total, before.total, 1))
        let compareCard = TokenBoxView()
        compareCard.setRows([
            TokenContentKit.head(scope.title + " \(index) 时 · vs " + scope.otherTitle + "同时段", meta: "总量 " + tokenDelta),
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
            TokenContentKit.twoColumn([
                TokenContentKit.keyRow("占" + scope.title + "全天", TokenFormatting.percent(share)),
                TokenContentKit.keyRow("24 桶排名", "\(ranking) / \(buckets.count)"),
                TokenContentKit.keyRow("较同时段总量", tokenDelta),
                TokenContentKit.keyRow("较同时段请求", requestDelta),
            ]),
        ])

        return [TokenContentKit.hero(TokenFormatting.tokens(current.total), unit: "tok / 时",
                     sub: scope.title + " \(index):00–\(index):59 · 三段相加 = 该小时总 tok"),
                splitCard, compareCard, extraCard,
                TokenContentKit.note("口径：按小时桶仅「今日」与「昨日」可得；历史日只有天粒度，所以 7 / 30 天那排柱点开的是日详情。三段相加 = 该小时总 tok，请求数与 tok 不同源，不做除法换算。")]
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
        split.update(shares: TokenContentKit.splitShares(current),
                     colors: [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor, TokenPaneStyle.outputColor],
                     accessibility: current.label + " 三段拆分")
        let splitCard = TokenBoxView()
        splitCard.setRows([
            TokenContentKit.head("三段拆分 · 日汇总", meta: "占" + range.title + " " + TokenFormatting.percent(share)),
            split,
            TokenContentKit.twoColumn([
                TokenContentKit.keyRow("缓存读", TokenFormatting.tokens(current.cache), color: TokenPaneStyle.cacheInk),
                TokenContentKit.keyRow("未缓存", TokenFormatting.tokens(current.uncached), color: TokenPaneStyle.uncachedInk),
                TokenContentKit.keyRow("输出", TokenFormatting.tokens(current.output)),
                TokenContentKit.keyRow("请求数", TokenFormatting.grouped(current.request), color: TokenPaneStyle.requestInk),
            ]),
        ])

        let scale = Double(max(current.total, before.total, 1))
        let compareCard = TokenBoxView()
        compareCard.setRows([
            TokenContentKit.head("vs 前一日", meta: "总量 " + tokenDelta),
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
            TokenContentKit.twoColumn([
                TokenContentKit.keyRow("占窗口", TokenFormatting.percent(share)),
                TokenContentKit.keyRow("窗口内排名", "\(ranking) / \(buckets.count)"),
                TokenContentKit.keyRow("较前一日总量", tokenDelta),
                TokenContentKit.keyRow("较前一日请求", requestDelta),
            ]),
        ])

        return [TokenContentKit.hero(TokenFormatting.tokens(current.total), unit: "tok / 日",
                     sub: current.label + " · 日汇总 · 与前一日对比（仅天粒度）"),
                splitCard, compareCard, extraCard,
                TokenContentKit.note(TokenDistroCopy.dayBucketNote)]
    }

    /// 对比行：实现在 TokenContentKit（缓存屏的对照块共用同一份）
    func compareRow(name: String, text: String, fraction: Double, color: NSColor) -> NSView {
        TokenContentKit.compareRow(name: name, text: text, fraction: fraction, color: color)
    }
}