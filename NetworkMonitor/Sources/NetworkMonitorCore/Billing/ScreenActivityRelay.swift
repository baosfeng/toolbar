import Foundation

// MARK: - 屏幕活动状态去重派发（纯逻辑）

/// 屏幕活动状态机 —— 把「系统当前是否亮屏可用」收敛成「暂停 / 恢复 / 无动作」三种动作
///
/// 抽成值类型的原因：通知中心会重复投递同一状态（显示器休眠 + 系统休眠先后到达、
/// 30 秒自检与事件通知重叠），直接回调会让额度刷新被反复 pause / resume，
/// 每次 resume 都要强制拉一轮接口（Ollama 10 次/分钟限流会被打满）。
/// 判据独立后可被 TestRunner 直接断言边界，也让「什么时候该发请求」只有一个实现点。
public struct ScreenActivityRelay: Sendable, Equatable {

    /// 一次状态判定的结果
    public enum Event: Equatable, Sendable {
        /// 状态未变（首次为活跃也属此类）—— 不做事
        case none
        /// 刚进入不可用（锁屏 / 显示器休眠 / 系统休眠）—— 停止后台刷新
        case paused
        /// 刚从不可用恢复 —— 立即强制刷新一次
        case resumed
    }

    /// 上次已知的可用状态（nil = 首次判定，尚无基准）
    private var lastActive: Bool?

    public init(lastActive: Bool? = nil) {
        self.lastActive = lastActive
    }

    /// 是否已有基准（测试与排查用）
    public var hasBaseline: Bool { lastActive != nil }

    /// 消费一次「当前是否活跃」判定
    ///
    /// 规则：
    /// 1. 首次判定为活跃 → `.none`（启动即正常，无需额外刷新）；
    /// 2. 首次判定为不可用 → `.paused`（开机自启时屏幕仍锁着，必须立刻进暂停态）；
    /// 3. 与上次相同 → `.none`（通知重复投递不重复动作）；
    /// 4. 由不可用转活跃 → `.resumed`；由活跃转不可用 → `.paused`。
    public mutating func consume(active: Bool) -> Event {
        defer { lastActive = active }
        guard let last = lastActive else {
            return active ? .none : .paused
        }
        guard last != active else { return .none }
        return active ? .resumed : .paused
    }
}
