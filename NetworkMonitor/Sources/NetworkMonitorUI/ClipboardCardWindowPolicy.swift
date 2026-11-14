import Foundation

// MARK: - 卡片流滑动窗口

/// 卡片流滑动窗口 — 视图池与可见段的纯算术（不含 AppKit，可被 TestRunner 直接断言）
///
/// 卡片流只实例化「当前窗口」内的卡片视图：同一时刻最多 `windowSize` 张，
/// 其余条目靠窗口滑动 + 视图复用覆盖。窗口大小是内存上限的唯一旋钮：
/// 面板一次最多可见 3 张卡片（卡宽 176 + 间距 10，面板宽约 520），
/// 32 张足够覆盖「可见 3 张 + 方向键来回走 + 滚动复用」，再大只是空占视图。
public enum ClipboardCardWindowPolicy {

    /// 窗口大小：同一时刻最多保留的卡片视图数量
    public static let windowSize = 32

    /// 窗口边缘缓冲：选中项落在两端这么多条以内时滑动窗口
    ///
    /// 必须小于 `windowSize / 2`，否则选中项还没进入缓冲就已跨出窗口（滑不到）。
    public static let windowMargin = 8

    /// 条目数是否超出窗口（超出才需要滑动，否则窗口起点固定为 0）
    public static func needsSliding(itemCount: Int) -> Bool {
        itemCount > windowSize
    }

    /// 窗口起点：选中项离开缓冲带时把窗口重新居中到选中项，保证任意下标都能走到
    ///
    /// - Parameters:
    ///   - itemCount: 全部匹配项条数
    ///   - selectedIndex: 当前选中下标（负数按 0 处理）
    ///   - currentStart: 当前窗口起点
    ///   - force: true 强制重新居中（整屏重排后把窗口对齐到选中项）
    /// - Returns: 新的窗口起点（始终落在 `[0, itemCount - windowSize]`，条目不足时恒为 0）
    public static func windowStart(itemCount: Int,
                                   selectedIndex: Int,
                                   currentStart: Int,
                                   force: Bool) -> Int {
        guard needsSliding(itemCount: itemCount) else { return 0 }
        let selected = max(0, selectedIndex)
        let lowerBound = currentStart + windowMargin
        let upperBound = currentStart + windowSize - windowMargin
        let inside = selected >= lowerBound && selected < upperBound
        guard force || !inside else { return currentStart }
        return min(max(0, selected - windowSize / 2), itemCount - windowSize)
    }

    /// 窗口内应收纳的卡片数（视图池按它补建 / 隐藏多余视图）
    public static func visibleCount(itemCount: Int, windowStart: Int) -> Int {
        min(max(0, itemCount - max(0, windowStart)), windowSize)
    }
}
