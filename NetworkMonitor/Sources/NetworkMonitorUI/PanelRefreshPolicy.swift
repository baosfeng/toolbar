import Foundation
import NetworkMonitorCore

// MARK: - 面板刷新策略（纯逻辑）

/// 一轮 tick 的输入快照 —— 判定所需的一切都在这里，不读任何实例状态
///
/// 分页用稳定 id（String）而不是 App 层的 `MenuPanelTab`：UI 目标看不到那个枚举，
/// 而「本轮属于哪一页」要进看门狗心跳，故以 id 传递。
public struct PanelRefreshInput: Equatable, Sendable {
    /// 本轮时刻
    public let now: Date
    /// 上次中频刷新时刻
    public let lastMidRefresh: Date
    /// 上次系统页视图渲染时刻
    public let lastSystemRefresh: Date
    /// 当前渲染档位（节拍与中频间隔的唯一来源）
    public let tier: RenderTier
    /// 面板是否展开
    public let panelVisible: Bool
    /// 当前分页的稳定 id
    public let currentTabStableID: String

    public init(now: Date,
                lastMidRefresh: Date,
                lastSystemRefresh: Date,
                tier: RenderTier,
                panelVisible: Bool,
                currentTabStableID: String) {
        self.now = now
        self.lastMidRefresh = lastMidRefresh
        self.lastSystemRefresh = lastSystemRefresh
        self.tier = tier
        self.panelVisible = panelVisible
        self.currentTabStableID = currentTabStableID
    }
}

/// 本轮要做的动作 —— 控制器只按这份清单执行副作用，自己不再算判定
public struct PanelRefreshPlan: Equatable, Sendable {
    /// 本轮时刻（控制器用它回写两个「上次刷新时刻」）
    public let now: Date
    /// 本轮归属分页（看门狗心跳用）
    public let currentTabStableID: String
    /// 面板是否展开（同上）
    public let panelVisible: Bool
    /// 是否拉一次额度：标准 / 极致档收起时也拉（额度阈值提醒依赖它），省电档收起即停
    public let pullsBilling: Bool
    /// 是否刷新可见层：实时速率、折线采样、系统指标历史推进
    public let refreshesVisibleLayer: Bool
    /// 是否渲染系统页视图（5 秒闸门；到点才推快照与 Wi-Fi 链路条）
    public let rendersSystemViews: Bool
    /// 是否跑一次中频刷新（今日流量 / 柱状图 / 进程 / 系统信息）
    public let runsMidFrequency: Bool

    public init(now: Date,
                currentTabStableID: String,
                panelVisible: Bool,
                pullsBilling: Bool,
                refreshesVisibleLayer: Bool,
                rendersSystemViews: Bool,
                runsMidFrequency: Bool) {
        self.now = now
        self.currentTabStableID = currentTabStableID
        self.panelVisible = panelVisible
        self.pullsBilling = pullsBilling
        self.refreshesVisibleLayer = refreshesVisibleLayer
        self.rendersSystemViews = rendersSystemViews
        self.runsMidFrequency = runsMidFrequency
    }
}

/// tick 的三层判定：额度 → 可见层（含 5 秒系统页闸门）→ 中频闸门
///
/// 判定顺序与改造前的 `tick()` 逐条对应，只是把「要不要做」搬到这里：
/// - 额度判定在可见性判定之前（收起时也可能要拉）；
/// - 可见层要求面板展开，且档位没声明「收起停摆」（两条判据的与，保留原组合顺序）；
/// - 系统页 5 秒闸门固定间隔，不随档位变；中频闸门取档位的中频间隔。
///
/// 分页不参与上述层级判定：换页只改变「推给哪一页」，不改变刷新节拍。
public enum PanelRefreshPolicy {

    /// 系统页视图刷新间隔（秒）：与网络页中频刷新同一档
    public static let systemRefreshInterval: TimeInterval = 5.0

    public static func plan(_ input: PanelRefreshInput) -> PanelRefreshPlan {
        let profile = RenderTierLogic.profile(for: input.tier)
        // 省电档收起时连额度也不拉，换取真正的空闲（BillingMonitor 内部另有 60 秒节流与锁屏暂停）
        let pullsBilling = input.panelVisible || !profile.stopsTickWhenClosed
        let refreshesVisibleLayer = RenderTierLogic.shouldRefreshPanel(tier: input.tier,
                                                                      panelVisible: input.panelVisible)
            && input.panelVisible
        let rendersSystemViews = refreshesVisibleLayer
            && input.now.timeIntervalSince(input.lastSystemRefresh) >= systemRefreshInterval
        let runsMidFrequency = refreshesVisibleLayer
            && input.now.timeIntervalSince(input.lastMidRefresh) >= profile.midInterval
        return PanelRefreshPlan(now: input.now,
                                currentTabStableID: input.currentTabStableID,
                                panelVisible: input.panelVisible,
                                pullsBilling: pullsBilling,
                                refreshesVisibleLayer: refreshesVisibleLayer,
                                rendersSystemViews: rendersSystemViews,
                                runsMidFrequency: runsMidFrequency)
    }
}
