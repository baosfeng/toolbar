import Foundation

// MARK: - 来源收窄（跨源合计 → 单源）

/// 页头来源切换的数据侧桥接
///
/// 唯一职责：把「跨源合计快照」收窄成「单源快照」。快照是全同形的（日/时桶、项目/模型、
/// 窗口合计都由聚合层按同一套结构给出），所以四屏与二级页只要拿到收窄后的快照，
/// 口径自动跟随来源，视图层不必逐块判断「当前是哪个源」。
package enum TokenSourceScope {

    /// 收窄到单一来源；nil = 全部（原样返回跨源合计，不做任何合并/覆盖）
    package static func narrow(_ snapshot: HarnessUsageSnapshot,
                               to source: TokenSourceID?) -> HarnessUsageSnapshot {
        guard let source else { return snapshot }
        return snapshot.scoped(to: source)
    }

    /// 页名该写哪个来源（纯函数，TestRunner 可直接断言）
    ///
    /// - 选中了某个来源 → 写它；
    /// - 未选中且只有一个来源有数据 → 写它（此时「全部」等于它，写「全部」看不出在看什么）；
    /// - 未选中且 0 个或多个来源有数据 → nil（写「全部」）。
    package static func displaySource(selected: TokenSourceID?,
                                      dataSources: [TokenSourceID]) -> TokenSourceID? {
        if let selected { return selected }
        return dataSources.count == 1 ? dataSources.first : nil
    }

    /// 快照里「有数据的来源」：bySource 存在且（会话数 > 0 或用量非零）
    ///
    /// bySource 整份为空 = 老快照 / 单源时代的 fixture：整份快照就是 DSH 一家的合计，
    /// 按一个来源（`.legacy`）算，否则老数据会被当成「全部」而显示错页名。
    package static func dataSources(in snapshot: HarnessUsageSnapshot) -> [TokenSourceID] {
        let listed = sources(in: snapshot)
        if !listed.isEmpty { return listed }
        return snapshot.bySource.isEmpty ? [TokenSourceID.legacy] : []
    }

    /// 来源切换器菜单里可选的来源：有数据的（会话数 > 0 或用量非零）
    ///
    /// 未安装 / 装了但没有会话的来源不进菜单——它们归设置页的来源清单管，
    /// 塞进页头菜单只会让「切过去一片空」变成一个陷阱。
    package static func sources(in snapshot: HarnessUsageSnapshot) -> [TokenSourceID] {
        TokenSourceID.allCases.filter { id in
            guard let entry = snapshot.bySource[id] else { return false }
            return entry.sessionCount > 0 || !entry.usage.isZero
        }
    }
}
