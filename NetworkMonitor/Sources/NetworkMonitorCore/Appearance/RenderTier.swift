import Foundation

// MARK: - 渲染帧率档（纯值 + 纯函数，不依赖 AppKit）

/// 渲染档位标识
///
/// 口径说明（重要）：本项目**没有 CADisplayLink / 逐帧动画**，所有图表都是数据变化触发的
/// `draw(_:)` 重绘，动画是 `NSAnimationContext` / `CABasicAnimation` 一次性播放。
/// 因此「帧率档」在本项目落地为四件事：**刷新节拍**（状态栏与面板共用的那个 Timer）、
/// **动画是否播放与时长**、**玻璃材质是否参与合成**、**图表重采样上限**。
/// 档位不改变任何数据口径，只改变「多久刷新一次、刷多细」。
public enum RenderTier: String, CaseIterable, Sendable {
    case standard
    case extreme
    case powerSave

    public var displayName: String {
        switch self {
        case .standard: return "标准"
        case .extreme: return "极致"
        case .powerSave: return "省电"
        }
    }

    /// 设置页一句话说明（选题下拉副标题用）
    public var detail: String {
        switch self {
        case .standard: return "1 秒刷新、中频 5 秒，动效与玻璃全开，默认档。"
        case .extreme: return "0.5 秒刷新、中频 2 秒，折线采样点翻倍，交互玻璃随动。"
        case .powerSave: return "2 秒刷新、中频 15 秒，玻璃与动效关闭，图表降采样。"
        }
    }

    /// rawValue → 档位；非法值回落标准档
    public static func resolved(fromRaw raw: String) -> RenderTier {
        RenderTier(rawValue: raw) ?? .standard
    }
}

/// 档位展开后的全部可执行参数
///
/// 每个字段都直接对应一处消费方（Timer 周期 / 节流间隔 / 采样点上限 / 动画时长 / 玻璃开关 /
/// 图表条数），中间不再二次换算——换档时逐个喂给消费方即可，没有隐式推导。
public struct RenderTierProfile: Sendable, Equatable {

    /// 状态栏与面板共用的那个 Timer 周期（秒）
    public let tickInterval: TimeInterval
    /// 面板中频刷新节流（秒）：今日流量 / 近 6 日柱 / 进程 / 额度
    public let midInterval: TimeInterval
    /// 系统指标采样周期（秒）
    public let sampleInterval: TimeInterval
    /// 折线采样点上限（1 个点 = 1 个 tick）
    public let historyPoints: Int

    /// 是否播放动效（关 = 全部直接落终态，与「减弱动态效果」等价）
    public let motionEnabled: Bool
    /// 展开类动画时长（秒）
    public let motionExpand: TimeInterval
    /// 弹层动画时长（秒）
    public let motionOverlay: TimeInterval
    /// 列表错峰步长（秒）
    public let motionStagger: TimeInterval

    /// 是否启用玻璃材质（false = 卡片回不透明实色、面板不做窗口后模糊）
    public let glassEnabled: Bool
    /// 玻璃是否启用交互随动（`NSGlassEffectView.effectIsInteractive`，macOS 27+）
    public let glassInteractive: Bool
    /// 是否在启动后预热一次面板（省电档省掉这次首帧开销）
    public let prewarm: Bool

    /// 图表最多画几个桶（不足则降采样）
    public let chartBucketLimit: Int
    /// 排行屏最多几行
    public let rankingLimit: Int
    /// 迷你折线宽度（pt）
    public let sparkWidth: Double

    /// 面板收起时是否停掉 tick（省电档：收起后不再为面板做采样）
    public let stopsTickWhenClosed: Bool
}

/// 档位 → 参数的唯一映射（纯函数，TestRunner 直接断言）
public enum RenderTierLogic {

    /// 标准档：与改造前的默认行为逐项一致（1 秒 / 5 秒 / 60 点 / 动效全开）
    public static let standard = RenderTierProfile(
        tickInterval: 1.0,
        midInterval: 5.0,
        sampleInterval: 1.0,
        historyPoints: 60,
        motionEnabled: true,
        motionExpand: 0.34,
        motionOverlay: 0.22,
        motionStagger: 0.024,
        glassEnabled: true,
        glassInteractive: false,
        prewarm: true,
        chartBucketLimit: 24,
        rankingLimit: 8,
        sparkWidth: 54,
        stopsTickWhenClosed: false
    )

    /// 极致档：更密的节拍、翻倍采样点、动效略长、玻璃参与交互随动
    public static let extreme = RenderTierProfile(
        tickInterval: 0.5,
        midInterval: 2.0,
        sampleInterval: 0.5,
        historyPoints: 120,
        motionEnabled: true,
        motionExpand: 0.40,
        motionOverlay: 0.22,
        motionStagger: 0.024,
        glassEnabled: true,
        glassInteractive: true,
        prewarm: true,
        chartBucketLimit: 24,
        rankingLimit: 8,
        sparkWidth: 54,
        stopsTickWhenClosed: false
    )

    /// 省电档：放宽节拍、动效落终态、玻璃关闭、图表降采样、收起即停 tick
    public static let powerSave = RenderTierProfile(
        tickInterval: 2.0,
        midInterval: 15.0,
        sampleInterval: 3.0,
        historyPoints: 30,
        motionEnabled: false,
        motionExpand: 0.34,
        motionOverlay: 0.22,
        motionStagger: 0.024,
        glassEnabled: false,
        glassInteractive: false,
        prewarm: false,
        chartBucketLimit: 12,
        rankingLimit: 4,
        sparkWidth: 40,
        stopsTickWhenClosed: true
    )

    /// 档位 → 参数表
    public static func profile(for tier: RenderTier) -> RenderTierProfile {
        switch tier {
        case .standard: return standard
        case .extreme: return extreme
        case .powerSave: return powerSave
        }
    }

    // MARK: - 合成规则

    /// 玻璃是否生效：用户显式开关优先，未设置时跟随档位
    ///
    /// `override` 为 nil 表示「用户没动过这个开关」，此时省电档会自动关玻璃；
    /// 用户手动设过就尊重用户选择（不因为换档把人家刚打开的玻璃又关掉）。
    public static func effectiveGlass(override: Bool?, tier: RenderTier) -> Bool {
        override ?? profile(for: tier).glassEnabled
    }

    /// 本次 tick 是否应该刷新面板内容
    ///
    /// 省电档在面板收起时直接返回 false（连速率也不采），其余档收起时仍允许做后台类刷新。
    public static func shouldRefreshPanel(tier: RenderTier, panelVisible: Bool) -> Bool {
        panelVisible || !profile(for: tier).stopsTickWhenClosed
    }

    /// 图表实际画几个桶：可用数据不足时按可用数，超上限时按降采样后的上限
    ///
    /// 降采样按「合并相邻两点」取平均前的整数步长，保证桶宽均匀不错位。
    public static func chartBuckets(available: Int, tier: RenderTier) -> Int {
        let limit = profile(for: tier).chartBucketLimit
        guard available > limit, limit > 1 else { return min(max(available, 0), limit) }
        return limit
    }

    /// 折线采样点上限
    public static func historyLimit(tier: RenderTier) -> Int {
        profile(for: tier).historyPoints
    }

    /// 排行行数上限
    public static func rankingLimit(tier: RenderTier) -> Int {
        profile(for: tier).rankingLimit
    }

    /// 给日志 / 调试面板的一行摘要（切档自证用）
    public static func summary(for tier: RenderTier) -> String {
        let p = profile(for: tier)
        return "档位=\(tier.displayName) tick=\(p.tickInterval)s 中频=\(p.midInterval)s "
            + "采样=\(p.sampleInterval)s 点数=\(p.historyPoints) 动效=\(p.motionEnabled ? "开" : "关") "
            + "玻璃=\(p.glassEnabled ? "开" : "关") 桶=\(p.chartBucketLimit) 排行=\(p.rankingLimit)"
    }
}
