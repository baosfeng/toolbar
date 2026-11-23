import Foundation

// MARK: - Token 页分屏契约（纯逻辑：屏标题 / 区块归属 / 屏页脚）

/// Token 页的 2 个屏 —— 屏切换条的段落顺序即 allCases 顺序
///
/// 存在理由：改前 4 屏（概览 / 用量 / 缓存 / 排行）每屏只用掉约 300/409pt，
/// 下方常年一片空白，看一次完整数据要切三次屏且上下文全丢。收敛到 2 屏后
/// 每屏都填满内容区：总览屏 = 一眼看「现在用了多少、长什么样」，
/// 分布屏 = 一眼看「花在哪个项目 / 模型 / 工具上」。
///
/// 缓存命中从独立屏降级为**面板内二级页**（TokenDetailKind.cache）：
/// 它本质是对一个比率的多角度展开（环 / 走势 / 对照 / 统计），
/// 主面板只需要一条可点的命中率条。
///
/// 归属写错在截图里很难看出来（同一块画两遍 / 某块哪屏都不显示），
/// 所以把归属做成纯逻辑：本 target 不依赖 AppKit 与 Core，TestRunner 可直接断言。
///
/// 一个屏 = 内容（区块自顶向下，超出走屏内滚动）+ 页脚（固定屏底，见 TokenScreenFooter）。
public enum TokenScreen: Int, CaseIterable, Sendable {
    case overview
    case distro

    /// 屏标题（同时用作屏切换条的分段文案）
    public var title: String {
        switch self {
        case .overview: return "总览"
        case .distro: return "分布"
        }
    }

    /// 屏标题（顺序 = 屏切换条的段顺序）
    public static var titles: [String] { allCases.map(\.title) }

    /// 本屏包含的区块（顺序 = 屏内自顶向下的排布顺序）
    public var blocks: [TokenScreenBlock] { TokenScreenBlock.allCases.filter { $0.screen == self } }

    /// 本屏页脚 —— 两屏都是状态带（峰 / 昨 / 缓存 / 命中）
    public var footer: TokenScreenFooter { .stateBand }

    /// 某区块属于哪一屏
    public static func screen(for block: TokenScreenBlock) -> TokenScreen { block.screen }

    /// 某屏的区块列表（视图按它装配，测试按它断言覆盖完整）
    public static func blocks(for screen: TokenScreen) -> [TokenScreenBlock] { screen.blocks }

    /// 某屏的页脚
    public static func footer(for screen: TokenScreen) -> TokenScreenFooter { screen.footer }
}

/// 屏页脚 —— 固定钉在屏底，内容滚动时不动（两屏高度因此一致）
public enum TokenScreenFooter: Int, CaseIterable, Sendable {
    /// 底部状态带（峰 / 昨 / 缓存 / 命中），两屏共用同一份 model.stateBand
    case stateBand

    /// 页脚中文名（快照台账用）
    public var title: String {
        switch self {
        case .stateBand: return "状态带"
        }
    }
}

/// 主面板区块 —— 每个区块唯一归属一屏
///
/// 缓存环 / 命中率走势 / 本周期对照 / 样本统计四块**不在枚举里**：
/// 它们已降级为二级页内容（TokenDetailKind.cache），不再是主面板区块。
public enum TokenScreenBlock: Int, CaseIterable, Sendable {
    /// 首屏 Hero（范围总量 + 较昨日 + 实时）
    case hero
    /// 四族卡 2×2（未缓存输入 / 输出 / 缓存读 / 请求数）
    case familyCards
    /// 缓存命中紧凑条（小环 + 命中率大字 + 缓存读 / 未缓存 / 节省比例），整条可点进缓存二级页
    case cacheHit
    /// 主图（今日 24 桶 / 按天 N 桶），每根柱可点进单桶页
    case hourChart
    /// 分布屏整块（维度分段 + 占比条 + Top 8 两行式行 + 汇总），自带内容栈
    case distro
    /// 今日 vs 昨日同期（分布屏底部，与 Hero 的同比较文案不同：这里给两条实际数值）
    case compare

    /// 归属的屏
    public var screen: TokenScreen {
        switch self {
        case .hero, .familyCards, .cacheHit, .hourChart: return .overview
        case .distro, .compare: return .distro
        }
    }

    /// 区块中文名（快照台账与读屏文案共用）
    public var title: String {
        switch self {
        case .hero: return "Hero"
        case .familyCards: return "四族卡"
        case .cacheHit: return "缓存命中条"
        case .hourChart: return "主图"
        case .distro: return "分布与占比条"
        case .compare: return "今日 vs 昨日"
        }
    }
}
