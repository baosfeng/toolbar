import Foundation
import NetworkMonitorCore

// MARK: - Token 页展示模型

/// 统计范围
enum TokenRange: Int, CaseIterable {
    case today
    case d7
    case d30

    /// 分段标题
    var title: String {
        switch self {
        case .today: return "今日"
        case .d7: return "近 7 天"
        case .d30: return "近 30 天"
        }
    }

    /// 窗口天数
    var days: Int {
        switch self {
        case .today: return 1
        case .d7: return 7
        case .d30: return 30
        }
    }
}

/// 小时图对比模式
enum TokenHourMode: Int, CaseIterable {
    case today
    case compare

    var title: String {
        switch self {
        case .today: return "今日"
        case .compare: return "比昨日"
        }
    }
}

/// 按天趋势形态
enum TokenTrendMode: Int, CaseIterable {
    case stack
    case line

    var title: String {
        switch self {
        case .stack: return "堆叠"
        case .line: return "折线"
        }
    }
}

/// Token 页展示模型 —— 由快照 + 交互状态派生出的只读视图数据
///
/// 视图层只做排版，不再重复计算占比 / 窗口 / 环比，保证同一份数据在各分区口径一致。
struct TokenPaneModel {

    /// 环比徽标（`value == nil` 时为「对比昨日 00–14 时」这类说明胶囊）
    struct Badge {
        let title: String
        let value: String?
        let isUp: Bool
    }

    /// 三项分卡
    struct Chip {
        let title: String
        let value: String
        let share: String
    }

    /// 趋势 / 小时图的一天（`usage == nil` 表示无会话，画斜纹）
    struct DayCell {
        let day: String
        let usage: HarnessTokenUsage?
    }

    /// 模型行
    struct ModelRow {
        let name: String
        let sub: String
        let share: Double
        let amount: String
        let colorIndex: Int
    }

    /// 项目行
    struct ProjectRow {
        let name: String
        let sub: String
        let amount: String
        let share: Double
    }

    let heroValue: String
    let heroLabel: String
    let windowLabel: String
    let badges: [Badge]
    /// 环比说明（如「对比昨日 00–17 时」），独立成一行小字
    let compareNote: String?
    let hourly: [HarnessHourlyUsage]
    let yesterdayHourly: [HarnessHourlyUsage]
    let currentHour: Int
    let hourNote: String
    let chips: [Chip]
    let reuseValue: String
    let reuseSeries: [Double?]
    let requestValue: String
    let requestTag: String
    let requestBars: [Int?]
    let trend: [DayCell]
    let trendWindowLabel: String
    let trendAxis: [String]
    let models: [ModelRow]
    let projects: [ProjectRow]
    let weekParts: [String]
    let totalParts: [String]
    let footer: [String]
    /// 折叠态摘要（一行高效信息，不是标题重复）
    let trendSummary: String
    let modelSummary: String
    let projectSummary: String
    let totalsSummary: String
    /// 展开态头部说明
    let modelMeta: String
    let projectMeta: String
    /// 有数据的天数（环比 / 头部说明口径）
    let dayCount: Int
    let hasData: Bool

    /// 由快照与交互状态派生展示模型
    static func make(snapshot: HarnessUsageSnapshot,
                     range: TokenRange,
                     hourMode: TokenHourMode,
                     now: Date = Date()) -> TokenPaneModel {
        let currentHour = HarnessTokenTimeWindow.hourIndex(forTsMs: Int64(now.timeIntervalSince1970 * 1000))
        let lastDay = HarnessTokenTimeWindow.dayKey(for: now)
        let dailyUsage = snapshot.daily.reduce(into: [String: HarnessTokenUsage]()) { result, item in
            result[item.day] = item.usage
        }

        // 范围合计（今日直接取数据层聚合结果，避免与 hourly 口径重复相加）
        let rangeKeys = TokenFormat.dayKeys(lastDay: lastDay, days: range.days)
        var rangeUsage = HarnessTokenUsage.zero
        for key in rangeKeys {
            if let usage = dailyUsage[key] { rangeUsage = rangeUsage.adding(usage) }
        }
        let heroUsage = range == .today ? snapshot.totals.today : rangeUsage
        let threeWay = heroUsage.uncachedInput + heroUsage.output + heroUsage.cacheRead

        // 环比：今日 vs 昨日同期（同 0…currentHour 时）
        let todaySoFar = TokenComparison.sum(hourly: snapshot.todayHourly, throughHour: currentHour)
        let yesterdaySoFar = TokenComparison.sum(hourly: snapshot.yesterdayHourly, throughHour: currentHour)
        var badges: [Badge] = []
        var compareNote: String?
        if range == .today {
            let metrics: [(String, Int, Int)] = [
                ("输入", todaySoFar.uncachedInput, yesterdaySoFar.uncachedInput),
                ("输出", todaySoFar.output, yesterdaySoFar.output),
                ("缓存", todaySoFar.cacheRead, yesterdaySoFar.cacheRead),
                ("请求", todaySoFar.requestCount, yesterdaySoFar.requestCount),
            ]
            for (title, today, yesterday) in metrics {
                guard let delta = TokenComparison.delta(today: today, yesterday: yesterday) else { continue }
                badges.append(Badge(title: title, value: delta.text, isUp: delta.direction == .up))
            }
            if !badges.isEmpty {
                compareNote = "对比昨日 00–\(currentHour) 时"
            }
        }

        // 三项分卡
        func shareText(_ value: Int) -> String {
            guard threeWay > 0 else { return "占合计 —" }
            return "占合计 " + TokenFormat.percent(Double(value) / Double(threeWay))
        }
        let chips = [
            Chip(title: "未缓存输入", value: TokenFormat.abbreviated(heroUsage.uncachedInput),
                 share: shareText(heroUsage.uncachedInput)),
            Chip(title: "输出", value: TokenFormat.abbreviated(heroUsage.output),
                 share: shareText(heroUsage.output)),
            Chip(title: "缓存读", value: TokenFormat.abbreviated(heroUsage.cacheRead),
                 share: shareText(heroUsage.cacheRead)),
        ]

        // 缓存复用率：当前范围口径 + 近 30 天按天序列（无数据日为 nil，折线断开）
        let reuseRate = HarnessCacheHitRate.compute(cacheRead: heroUsage.cacheRead,
                                                    uncachedInput: heroUsage.uncachedInput)
        let reuseSeries: [Double?] = TokenFormat.dayKeys(lastDay: lastDay, days: 30).map { key in
            guard let usage = dailyUsage[key] else { return nil }
            return HarnessCacheHitRate.compute(cacheRead: usage.cacheRead, uncachedInput: usage.uncachedInput)
        }

        // 请求数：今日按小时，其它范围按天
        let requestBars: [Int?]
        let requestTag: String
        if range == .today {
            // 按 hour 字段归位到 0…23 槽，缺省小时保留空位：即使上游只返回有数据的槽，
            // 小图也不会把柱子压缩到左侧（缺陷 B 的根因防线）
            var slots = [Int?](repeating: nil, count: 24)
            for slot in snapshot.todayHourly where (0..<24).contains(slot.hour) {
                slots[slot.hour] = slot.usage?.requestCount
            }
            requestBars = slots
            requestTag = "今日 · 按小时"
        } else {
            requestBars = rangeKeys.map { dailyUsage[$0]?.requestCount }
            requestTag = "本范围 · 按天"
        }

        // 按天趋势：今日范围展示近 7 天，其余跟随范围
        let trendDays = range == .d30 ? 30 : 7
        let trendKeys = TokenFormat.dayKeys(lastDay: lastDay, days: trendDays)
        let trend = trendKeys.map { DayCell(day: $0, usage: dailyUsage[$0]) }
        let middleKey = trendKeys[trendKeys.count / 2]

        // 模型：Top 5 + 其它（累计口径）
        let modelTotal = snapshot.models.reduce(0) { $0 + $1.usage.totalTokens }
        var models: [ModelRow] = snapshot.models.prefix(5).enumerated().map { index, item in
            let tokens = item.usage.totalTokens
            let share = modelTotal > 0 ? Double(tokens) / Double(modelTotal) : 0
            let provider = item.provider.isEmpty ? "" : item.provider + " · "
            return ModelRow(name: item.model,
                            sub: provider + TokenFormat.percent(share, decimals: 0),
                            share: share,
                            amount: TokenFormat.abbreviated(tokens),
                            colorIndex: index)
        }
        let restModels = snapshot.models.dropFirst(5)
        if !restModels.isEmpty {
            let restTokens = restModels.reduce(0) { $0 + $1.usage.totalTokens }
            let share = modelTotal > 0 ? Double(restTokens) / Double(modelTotal) : 0
            models.append(ModelRow(name: "其它 \(restModels.count) 个模型",
                                   sub: TokenFormat.percent(share, decimals: 0),
                                   share: share,
                                   amount: TokenFormat.abbreviated(restTokens),
                                   colorIndex: 5))
        }

        // 项目：Top 5（累计口径）
        let projectTotal = snapshot.projects.reduce(0) { $0 + $1.usage.totalTokens }
        let projects: [ProjectRow] = snapshot.projects.prefix(5).map { item in
            let tokens = item.usage.totalTokens
            let share = projectTotal > 0 ? Double(tokens) / Double(projectTotal) : 0
            return ProjectRow(name: item.displayName,
                              sub: "\(item.sessionCount) 会话 · 占 " + TokenFormat.percent(share, decimals: 0),
                              amount: TokenFormat.abbreviated(tokens),
                              share: share)
        }

        // 本周 / 累计摘要
        func parts(_ usage: HarnessTokenUsage) -> [String] {
            [TokenFormat.abbreviated(usage.uncachedInput),
             TokenFormat.abbreviated(usage.output),
             TokenFormat.abbreviated(usage.cacheRead)]
        }
        let weekParts = parts(snapshot.totals.thisWeek)
        let totalParts = parts(snapshot.totals.allTime)

        // 页脚：有数据日跨度 / 会话数 / 请求数 + 口径说明
        var footer: [String] = []
        if let first = snapshot.daily.first?.day, let last = snapshot.daily.last?.day {
            footer.append("\(snapshot.daily.count) 个有数据日 · \(first) 至 \(last) · "
                          + "\(snapshot.indexedSessions) 会话 · "
                          + TokenFormat.grouped(snapshot.totals.allTime.requestCount) + " 次请求")
        } else {
            footer.append("\(snapshot.indexedSessions) 会话 · 暂无统计数据")
        }
        footer.append("口径：assistant 消息 usage 字段；in/out 段占比极小时按 2px 保底显示，数值仍为真实值")

        // 折叠态摘要：窗口合计 / 峰值、模型与项目 Top1 占比、本周与累计三项
        var trendTotal = 0
        var peakUsage = 0
        var peakDay = ""
        for cell in trend {
            guard let usage = cell.usage else { continue }
            let tokens = UsageTotal.of(usage)
            trendTotal += tokens
            if tokens > peakUsage {
                peakUsage = tokens
                peakDay = cell.day
            }
        }
        let trendSummary = "近 \(trendDays) 天 · 合计 " + TokenFormat.abbreviated(trendTotal)
            + (peakUsage > 0 ? " · 峰值 " + TokenFormat.mmdd(peakDay) + " " + TokenFormat.abbreviated(peakUsage) : "")
        let modelSummary: String
        if let top = snapshot.models.first, modelTotal > 0 {
            let share = Double(top.usage.totalTokens) / Double(modelTotal)
            modelSummary = "\(snapshot.models.count) 个模型 · " + top.model + " 占 " + TokenFormat.percent(share, decimals: 0)
        } else {
            modelSummary = "暂无模型数据"
        }
        let projectSummary: String
        if let top = snapshot.projects.first, projectTotal > 0 {
            let share = Double(top.usage.totalTokens) / Double(projectTotal)
            projectSummary = "\(snapshot.projects.count) 个项目 · " + top.displayName + " 占 " + TokenFormat.percent(share, decimals: 0)
        } else {
            projectSummary = "暂无项目数据"
        }
        func slashParts(_ usage: HarnessTokenUsage) -> String {
            // 紧凑写法：320pt 下折叠行要能放下「本周 · 累计」六个数值
            [TokenFormat.abbreviated(usage.uncachedInput),
             TokenFormat.abbreviated(usage.output),
             TokenFormat.abbreviated(usage.cacheRead)].joined(separator: "/")
        }
        let totalsSummary = "本周 " + slashParts(snapshot.totals.thisWeek)
            + " · 累计 " + slashParts(snapshot.totals.allTime)

        return TokenPaneModel(
            heroValue: TokenFormat.abbreviated(threeWay),
            heroLabel: range == .today ? "今日 · 截至 " + nowLabel(now) : range.title,
            windowLabel: range == .today ? "24 小时" : "\(trend.filter { $0.usage != nil }.count) 个有数据日",
            badges: badges,
            compareNote: compareNote,
            hourly: snapshot.todayHourly,
            yesterdayHourly: snapshot.yesterdayHourly,
            currentHour: currentHour,
            hourNote: hourMode == .compare
                ? "实心=今日 · 灰=昨日 00–\(currentHour) 时"
                : "0–\(currentHour) 时有会话",
            chips: chips,
            reuseValue: TokenFormat.percent(reuseRate),
            reuseSeries: reuseSeries,
            requestValue: TokenFormat.grouped(heroUsage.requestCount),
            requestTag: requestTag,
            requestBars: requestBars,
            trend: trend,
            trendWindowLabel: trendDays == 30 ? "近 30 天" : "近 7 天",
            trendAxis: [TokenFormat.mmdd(trendKeys[0]),
                        TokenFormat.mmdd(middleKey),
                        TokenFormat.mmdd(trendKeys[trendKeys.count - 1])],
            models: models,
            projects: projects,
            weekParts: weekParts,
            totalParts: totalParts,
            footer: footer,
            trendSummary: trendSummary,
            modelSummary: modelSummary,
            projectSummary: projectSummary,
            totalsSummary: totalsSummary,
            modelMeta: "\(snapshot.daily.count) 天累计 · Top 5 + 其它",
            projectMeta: "\(snapshot.daily.count) 天累计 · 会话数",
            dayCount: snapshot.daily.count,
            hasData: !TokenComparison.isEmpty(snapshot))
    }

    /// 当前时刻 HH:mm（Asia/Shanghai）
    private static func nowLabel(_ now: Date) -> String {
        let components = HarnessTokenTimeWindow.calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}