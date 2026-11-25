import Foundation
import NetworkMonitorCore

// MARK: - 额度页范围对齐（纯逻辑，可单测）

/// 首帧范围对齐 —— 页级范围与 provider 各自用量范围不一致时，要逐家通知哪些
///
/// 存在理由（用户投诉「默认进入额度 tab 图表都不显示，切到 24 小时再切回来才有了」）：
/// 页级初值是 7 天（`BillingPaneView.range`），而 provider 的 usage range 初值是
/// `supportedUsageRanges.first`（Open Design 声明 [24h, 7d] → first = 24h）。
/// 图表聚合严格要求 `usage.range == 页级 range`（不拿旧范围的数据冒充新范围），
/// 于是首帧过滤为空 → 柱图与轴隐藏、只剩「暂无用量数据」。
///
/// 切回 7d 之所以能好：那次点击真的走了一遍 `applyRange` → 逐家 `selectRange`。
/// 首帧缺的就是这一步，本函数把「该通知谁」的判据抽出来，让首帧复用同一套口径。
///
/// 判据三条（与 `BillingMonitor.selectRange` 的闸门同源，避免首帧发出必然被丢弃的调用）：
/// 1. `supportsUsage`：纯余额型 provider 没有用量请求可发；
/// 2. `supportedRanges` 含页级范围：provider 不支持的档切过去必然 400；
/// 3. `currentRange` 与页级不同：已经一致的不该再打一次请求出网。
public enum BillingRangeAlignment {

    /// 一家 provider 的对齐输入（视图层从 ProviderState 映射过来）
    public struct Candidate: Equatable {
        /// 实例标识
        public let id: String
        /// 是否提供用量明细
        public let supportsUsage: Bool
        /// 该 provider 支持的用量范围
        public let supportedRanges: [BillingRange]
        /// 当前选中的用量范围
        public let currentRange: BillingRange

        public init(id: String, supportsUsage: Bool,
                    supportedRanges: [BillingRange], currentRange: BillingRange) {
            self.id = id
            self.supportsUsage = supportsUsage
            self.supportedRanges = supportedRanges
            self.currentRange = currentRange
        }
    }

    /// 需要通知切档的 provider id（按传入顺序）
    public static func idsNeedingAlignment(_ candidates: [Candidate],
                                           pageRange: BillingRange) -> [String] {
        candidates.filter { candidate in
            candidate.supportsUsage
                && candidate.supportedRanges.contains(pageRange)
                && candidate.currentRange != pageRange
        }
        .map(\.id)
    }
}
