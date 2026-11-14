// MARK: - 分页懒装配记账（可断言纯逻辑）

/// 分页懒装配登记表 — 「这一页建过没有、要不要新建」的唯一判据
///
/// 存在理由：面板六个分页原先在 `MenuPanelView.init` 里一次全建（约 2800 个 layer-backed
/// 视图、14214 条约束常驻，启动三分钟 footprint 140 MB 的主体）。改成「首次切到才建」之后，
/// 判定必须是一处可与 AppKit 脱钩断言的逻辑，而不是散在视图里的 `if let` 猜：
/// 这里只记「哪些页已装配、每页装配了几次」，TestRunner 直接断言
/// 未切页前为空、切页后非空、重复切页不重建。
public struct PaneAssemblyLedger<Key: Hashable> {

    /// 已装配的分页
    private var assembledKeys: Set<Key> = []
    /// 每个分页被真正创建的次数（正常恒为 1；大于 1 说明同一页被重复建了）
    private var assemblyCounts: [Key: Int] = [:]

    public init() {}

    /// 该分页是否已装配
    public func isAssembled(_ key: Key) -> Bool { assembledKeys.contains(key) }

    /// 已装配的分页数
    public var assembledCount: Int { assembledKeys.count }

    /// 该分页被创建过几次（未装配 = 0）
    public func assemblyCount(for key: Key) -> Int { assemblyCounts[key] ?? 0 }

    /// 请求装配某分页 —— 返回 true 表示首次装配（调用方需新建实例并进视图树），
    /// 返回 false 表示已装配（调用方必须复用旧实例：不重建、不重复加约束）
    @discardableResult
    public mutating func requestAssembly(_ key: Key) -> Bool {
        guard assembledKeys.insert(key).inserted else { return false }
        assemblyCounts[key, default: 0] += 1
        return true
    }
}
