import Foundation

// MARK: - Token 页分屏契约（纯逻辑：屏标题 / 区块归属 / 屏页脚）

/// Token 页的 4 个屏 —— 屏切换条的段落顺序即 allCases 顺序
///
/// 存在理由：改前 8 个区块堆在一屏（520pt 内既看不到图表也看不到分布），
/// 分屏后每个区块必须**唯一**归属某个屏。归属写错在截图里很难看出来
/// （同一块画两遍 / 某块哪屏都不显示），所以把归属做成纯逻辑：
/// 本 target 不依赖 AppKit 与 Core，TestRunner 可直接断言。
///
/// 一个屏 = 内容（区块自顶向下，超出走屏内滚动）+ 页脚（固定屏底，见 TokenScreenFooter）。
public enum TokenScreen: Int, CaseIterable, Sendable {
    case overview
    case usage
    case cache
    case ranking

    /// 屏标题（同时用作屏切换条的分段文案）
    public var title: String {
        switch self {
        case .overview: return "概览"
        case .usage: return "用量"
        case .cache: return "缓存"
        case .ranking: return "排行"
        }
    }

    /// 屏标题（顺序 = 屏切换条的段顺序）
    public static var titles: [String] { allCases.map(\.title) }

    /// 本屏包含的区块（顺序 = 屏内自顶向下的排布顺序）
    public var blocks: [TokenScreenBlock] { TokenScreenBlock.allCases.filter { $0.screen == self } }

    /// 本屏页脚（概览 / 用量 / 排行 = 状态带，缓存 = 口径说明）
    public var footer: TokenScreenFooter { self == .cache ? .cacheNote : .stateBand }

    /// 某区块属于哪一屏
    public static func screen(for block: TokenScreenBlock) -> TokenScreen { block.screen }

    /// 某屏的区块列表（视图按它装配，测试按它断言覆盖完整）
    public static func blocks(for screen: TokenScreen) -> [TokenScreenBlock] { screen.blocks }

    /// 某屏的页脚
    public static func footer(for screen: TokenScreen) -> TokenScreenFooter { screen.footer }
}

/// 屏页脚 —— 固定钉在屏底，内容滚动时不动（四屏高度因此一致）
public enum TokenScreenFooter: Int, CaseIterable, Sendable {
    /// 底部状态带（峰 / 昨 / 索引 / 缓存），三屏共用同一份 model.stateBand
    case stateBand
    /// 缓存口径说明（命中率分母 / 上一周期来源 / 不折算金额）
    case cacheNote

    /// 页脚中文名（快照台账用）
    public var title: String {
        switch self {
        case .stateBand: return "状态带"
        case .cacheNote: return "口径说明"
        }
    }
}

/// 主面板区块 —— 每个区块唯一归属一屏
public enum TokenScreenBlock: Int, CaseIterable, Sendable {
    /// 首屏 Hero（范围总量 + 较昨日 + 实时）
    case hero
    /// 四族卡 2×2（未缓存输入 / 输出 / 缓存读 / 请求数）
    case familyCards
    /// 缓存命中紧凑条（小环 + 命中率大字 + 缓存读 / 未缓存 / 节省比例）
    case cacheHit
    /// 近 14 天迷你走势（概览屏补密度用；用量屏另有整高天趋势卡）
    case overviewTrend
    /// 今日 vs 昨日同期（概览屏）
    case compare
    /// 主图（今日 24 桶 / 按天 N 桶）
    case hourChart
    /// 天趋势（固定 14 天，整屏高度）
    case trend
    /// 缓存命中大环 + 四行拆分
    case cacheRing
    /// 命中率趋势（空缺桶断开不画 0）
    case cacheTrend
    /// 本周期 vs 上一周期
    case cacheCompare
    /// 样本统计
    case cacheStats
    /// 排行维度分段 + 占比条
    case distroBar
    /// 排行 Top 8 行 + 计数
    case distroRows

    /// 归属的屏
    public var screen: TokenScreen {
        switch self {
        case .hero, .familyCards, .cacheHit, .overviewTrend, .compare: return .overview
        case .hourChart, .trend: return .usage
        case .cacheRing, .cacheTrend, .cacheCompare, .cacheStats: return .cache
        case .distroBar, .distroRows: return .ranking
        }
    }

    /// 区块中文名（快照台账与读屏文案共用）
    public var title: String {
        switch self {
        case .hero: return "Hero"
        case .familyCards: return "四族卡"
        case .cacheHit: return "缓存命中条"
        case .overviewTrend: return "近 14 天走势"
        case .compare: return "今日 vs 昨日"
        case .hourChart: return "主图"
        case .trend: return "天趋势"
        case .cacheRing: return "缓存环与拆分"
        case .cacheTrend: return "命中率趋势"
        case .cacheCompare: return "本周期 vs 上周期"
        case .cacheStats: return "样本统计"
        case .distroBar: return "维度分段与占比条"
        case .distroRows: return "Top 8 与计数"
        }
    }
}
