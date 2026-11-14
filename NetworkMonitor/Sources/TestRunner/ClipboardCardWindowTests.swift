import Foundation
import NetworkMonitorUI

// MARK: - 卡片流滑动窗口（视图池上限）

/// 卡片流视图池窗口的口径守卫：32 张上限 + 任意下标可达
///
/// 内存背景：窗口内的每张卡片都常驻 8 个 layer-backed 子视图与一组约束，
/// 原 120 张窗口在面板打开后固定占住约 14MB footprint；降到 32 张后实测降至 147.8M（改前 162.2M）。
func runClipboardCardWindowTests() {
    print("🧪 Testing clipboard card window policy...")

    assertEqual(ClipboardCardWindowPolicy.windowSize, 32, "窗口 32 张（原 120）")
    assertEqual(ClipboardCardWindowPolicy.windowMargin, 8, "缓冲带 8 条")
    assertEqual(ClipboardCardWindowPolicy.needsSliding(itemCount: 32), false, "正好一屏不滑动")
    assertEqual(ClipboardCardWindowPolicy.needsSliding(itemCount: 33), true, "多一条即需要滑动")

    // 可见条数
    assertEqual(ClipboardCardWindowPolicy.visibleCount(itemCount: 10, windowStart: 0), 10, "条目不足窗口时全可见")
    assertEqual(ClipboardCardWindowPolicy.visibleCount(itemCount: 421, windowStart: 0), 32, "条目超出窗口时最多 32 张")
    assertEqual(ClipboardCardWindowPolicy.visibleCount(itemCount: 421, windowStart: 400), 21, "窗口末尾只剩 21 条")
    assertEqual(ClipboardCardWindowPolicy.visibleCount(itemCount: 0, windowStart: 0), 0, "空列表无卡片")
    assertEqual(ClipboardCardWindowPolicy.visibleCount(itemCount: 5, windowStart: 9), 0, "起点越过条目数时为 0")

    // 窗口滑动：缓冲带内不滑、跨出后居中到选中项
    assertEqual(ClipboardCardWindowPolicy.windowStart(itemCount: 421, selectedIndex: 5,
                                                      currentStart: 0, force: false), 0,
                "缓冲带内选中不滑动")
    assertEqual(ClipboardCardWindowPolicy.windowStart(itemCount: 421, selectedIndex: 100,
                                                      currentStart: 0, force: false), 84,
                "跨出缓冲带后窗口居中到选中项")
    assertEqual(ClipboardCardWindowPolicy.windowStart(itemCount: 421, selectedIndex: 420,
                                                      currentStart: 0, force: true), 389,
                "末尾下标把窗口顶到列表尾部")
    assertEqual(ClipboardCardWindowPolicy.windowStart(itemCount: 10, selectedIndex: 9,
                                                      currentStart: 0, force: true), 0,
                "条目不足窗口时起点恒 0")
    assertEqual(ClipboardCardWindowPolicy.windowStart(itemCount: 421, selectedIndex: -3,
                                                      currentStart: 0, force: true), 0,
                "负下标按 0 处理")

    // 任意下标可达：正向按方向键从头走到尾，选中项必须始终落在窗口内
    let itemCount = 421
    var start = 0
    var unreachable: [Int] = []
    for index in 0..<itemCount {
        start = ClipboardCardWindowPolicy.windowStart(itemCount: itemCount, selectedIndex: index,
                                                      currentStart: start, force: false)
        let visible = ClipboardCardWindowPolicy.visibleCount(itemCount: itemCount, windowStart: start)
        if index < start || index >= start + visible { unreachable.append(index) }
    }
    assertEqual(unreachable.isEmpty, true, "0…420 正向逐个下移都能落进窗口")

    // 反向走一遍（从尾部回到头部）
    start = itemCount - ClipboardCardWindowPolicy.windowSize
    unreachable = []
    for index in stride(from: itemCount - 1, through: 0, by: -1) {
        start = ClipboardCardWindowPolicy.windowStart(itemCount: itemCount, selectedIndex: index,
                                                      currentStart: start, force: false)
        let visible = ClipboardCardWindowPolicy.visibleCount(itemCount: itemCount, windowStart: start)
        if index < start || index >= start + visible { unreachable.append(index) }
    }
    assertEqual(unreachable.isEmpty, true, "420…0 反向逐个上移都能落进窗口")

    print("✅ Clipboard 卡片流窗口 works")
}
