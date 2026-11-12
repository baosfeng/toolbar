// MARK: - 面板分页高度预算（可断言纯逻辑）

/// 面板高度预算 — 五页统一页头 / 页脚之后，「这一页还装得下多少内容」
///
/// 存在理由：面板外框上限 520pt 是 popover 的硬约束，页头行 22pt 与状态带 20pt
/// 补齐后**同一条版式骨架**下各页的可用内容高度必须能算出来，否则「加个页头」
/// 就会把网络页顶出滚动条，而且只有跑起来才发现。这里把外框扣减写成纯函数，
/// TestRunner 直接断言，页面侧只读结果、不再各自累加。
public enum PaneHeightBudget {

    /// 面板总高上限（与 MenuPanelStyle.maxHeight 同源，此处不 import AppKit）
    public static let panelMaxHeight: Double = 520
    /// 面板顶部内边距
    public static let topInset: Double = 10
    /// 分页条高度
    public static let tabBarHeight: Double = 28
    /// 分页条与内容区间距
    public static let gapAfterTabBar: Double = 12
    /// 面板底部内边距
    public static let bottomInset: Double = 12
    /// 页头行高度
    public static let headerHeight: Double = 22
    /// 页头与内容区间距
    public static let gapAfterHeader: Double = 4
    /// 页脚状态带高度
    public static let bandHeight: Double = 20
    /// 内容区与页脚间距
    public static let gapBeforeBand: Double = 4

    /// 上下固定件的合计高度（分页条 + 页头 + 页脚 + 各自间距 + 面板内边距）
    public static func chromeHeight(hasHeader: Bool, hasBand: Bool) -> Double {
        var total = topInset + tabBarHeight + gapAfterTabBar + bottomInset
        if hasHeader { total += headerHeight + gapAfterHeader }
        if hasBand { total += gapBeforeBand + bandHeight }
        return total
    }

    /// 某页内容区的可用高度上限
    public static func paneBudget(hasHeader: Bool, hasBand: Bool) -> Double {
        panelMaxHeight - chromeHeight(hasHeader: hasHeader, hasBand: hasBand)
    }

    /// 给定内容自然高度，是否还装得下（不触发外框滚动）
    public static func fits(contentHeight: Double, hasHeader: Bool, hasBand: Bool) -> Bool {
        contentHeight <= paneBudget(hasHeader: hasHeader, hasBand: hasBand) + 0.5
    }

    /// 超出预算多少（负数 = 余量）
    public static func overflow(contentHeight: Double, hasHeader: Bool, hasBand: Bool) -> Double {
        contentHeight - paneBudget(hasHeader: hasHeader, hasBand: hasBand)
    }

    /// 收缩列表条数到预算内：返回还能放下几条整行
    ///
    /// - Parameters:
    ///   - fixedHeight: 列表之外固定部分的高度（页头 / 卡片 / 图表）
    ///   - rowHeight: 单行高度
    ///   - desired: 期望条数（数据上限）
    ///   - hasHeader / hasBand: 是否带页头与状态带
    public static func rowLimit(fixedHeight: Double, rowHeight: Double, desired: Int,
                                hasHeader: Bool, hasBand: Bool) -> Int {
        guard desired > 0, rowHeight > 0 else { return 0 }
        let available = paneBudget(hasHeader: hasHeader, hasBand: hasBand) - fixedHeight
        guard available > 0 else { return 0 }
        let rows = Int((available / rowHeight).rounded(.down))
        return min(desired, max(0, rows))
    }
}
