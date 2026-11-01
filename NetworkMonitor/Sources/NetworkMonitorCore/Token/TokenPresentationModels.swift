import Foundation

// MARK: - Token 页展示模型（定稿原型 final-定稿.html 口径）

/// 统计范围
package enum TokenRange: Int, CaseIterable {
    case today
    case d7
    case d30

    package var title: String {
        switch self {
        case .today: return "今日"
        case .d7: return "近 7 天"
        case .d30: return "近 30 天"
        }
    }

    /// 窗口天数
    package var days: Int {
        switch self {
        case .today: return 1
        case .d7: return 7
        case .d30: return 30
        }
    }

    /// 主图桶数：今日 24 小时桶，其余按天
    package var bucketCount: Int {
        self == .today ? 24 : days
    }
}

/// 小时图看哪一天（真换数据，不是换标签）
package enum TokenHourScope: Int, CaseIterable {
    case today
    case yesterday

    package var title: String { self == .today ? "今日" : "昨日" }
    package var otherTitle: String { self == .today ? "昨日" : "今日" }
}

/// 主图形态：堆叠三段 / 折线对比
package enum TokenHourView: Int, CaseIterable {
    case stack
    case compare

    package var title: String { self == .stack ? "堆叠" : "对比" }
}

/// 主图指标：三段总量 / 请求数
package enum TokenChartMetric: Int, CaseIterable {
    case total
    case request

    package var title: String { self == .total ? "总量" : "请求数" }
}

/// 天趋势形态：面积 / 分线
package enum TokenTrendMode: Int, CaseIterable {
    case stack
    case line

    package var title: String { self == .stack ? "面积" : "分线" }
}

/// 四个指标族
package enum TokenMetric: Int, CaseIterable {
    case uncached
    case output
    case cache
    case request

    package var title: String {
        switch self {
        case .uncached: return "未缓存输入"
        case .output: return "输出"
        case .cache: return "缓存读"
        case .request: return "请求数"
        }
    }

    /// 是否属于 tok 三段（请求数单独处理）
    package var isToken: Bool { self != .request }
}

/// 单桶（小时 / 天）用量
package struct TokenBucket {
    package let label: String
    package let uncached: Int
    package let output: Int
    package let cache: Int
    package let request: Int

    package static let empty = TokenBucket(label: "", uncached: 0, output: 0, cache: 0, request: 0)

    /// 三段相加 = 该桶总 tok（请求数与 tok 不同源，不进这个合计）
    package var total: Int { uncached + output + cache }

    package init(label: String, uncached: Int, output: Int, cache: Int, request: Int) {
        self.label = label
        self.uncached = uncached
        self.output = output
        self.cache = cache
        self.request = request
    }

    package init(label: String, usage: HarnessTokenUsage?) {
        self.label = label
        uncached = usage?.uncachedInput ?? 0
        output = usage?.output ?? 0
        cache = usage?.cacheRead ?? 0
        request = usage?.requestCount ?? 0
    }
}

/// 分族卡（2×2 首屏矩阵的一格）
package struct TokenFamilyCard {
    package let metric: TokenMetric
    package let title: String
    /// 数值主体（已缩写，如 1.30）
    package let value: String
    /// 单位（如 M tok / 次）
    package let unit: String
    /// 辅助行（同比与占比合并成一行，如「↑ 35% · 占 2.3%」）
    package let aux: String
    /// 辅助行是否为上行（决定墨色）
    package let deltaUp: Bool
    /// 辅助行是否为同比（false = 无同比时的日均文案，用三级色）
    package let hasDelta: Bool
    /// sparkline 序列（请求数卡画迷你柱）
    package let series: [Double]
}

/// 首屏 Hero（今日 / 当前范围的三项合计）
package struct TokenHero {
    /// 「今日总消耗」/「近 7 天总消耗」
    package let title: String
    /// 数值主体（已缩写，如 17.67）
    package let value: String
    /// 单位（如 M tok）
    package let unit: String
    /// 「较昨日 ↓ 23.3%」
    package let delta: String
    package let deltaUp: Bool
    /// 有无同比（昨日为 0 时没有，用三级色不编数）
    package let hasDelta: Bool
    /// 「实时 17:05」
    package let clock: String
}

/// 分布行（项目 / 模型）
package struct TokenDistroRow {
    package let rank: Int
    package let name: String
    /// provider 前缀（模型行用，其余为空）
    package let provider: String
    /// 第二行说明（模型详情的 provider + 占比）
    package let sub: String
    package let amount: String
    package let share: Double
    package let colorIndex: Int
}

/// 底状态带的一格
package struct TokenStateItem {
    package enum Tone {
        case plain
        case accent
        case cache
        case request
    }

    package let title: String
    package let value: String
    package let tone: Tone
}
