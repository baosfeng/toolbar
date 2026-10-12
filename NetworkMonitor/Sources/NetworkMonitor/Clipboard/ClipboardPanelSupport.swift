import AppKit
import NetworkMonitorCore

// MARK: - 面板检索纯逻辑

/// 面板检索与过滤 — 从面板控制器拆出的纯逻辑（控制器需守住单文件体积上限）
///
/// 职责：把「查询串 + 类型过滤」翻译为条目列表，不持有任何 UI 状态。
enum ClipboardPanelSearch {

    /// 取匹配项
    ///
    /// - 查询串非空：走仓储全文检索（覆盖 text / preview / 来源 App 名，长文本中段也能命中），
    ///   再用内存 rank 重排以保住相关度；
    /// - 查询串为空：用调用方给的全量副本做类型 / 收藏过滤；
    /// - 不做条数截断：返回全部匹配项，上限由调用方按偏好 maxItems 传 limit 决定。
    static func match(query: String,
                      filter: ClipboardFilter,
                      repository: any ClipboardRepository,
                      items: [ClipboardItem],
                      limit: Int) -> [ClipboardItem] {
        guard !query.isEmpty else { return items.filter { filter.matches($0) } }
        let candidates = repository.searchClipboardItems(query: query, limit: limit)
            .filter { filter.matches($0) }
        return rerank(query, candidates: candidates)
    }

    /// 相关度重排：rank 只认 preview + 来源 App 名，正文中段的命中在它那里得 0 分会被丢弃，
    /// 而这些正是全文检索新召回的目标，故按仓储原序补回尾部 —— 不丢命中，同时保住相关度排序
    private static func rerank(_ query: String, candidates: [ClipboardItem]) -> [ClipboardItem] {
        let ranked = ClipboardFuzzySearch.rank(query, items: candidates)
        let rankedIDs = Set(ranked.map(\.id))
        return ranked + candidates.filter { !rankedIDs.contains($0.id) }
    }
}

// MARK: - 面板定位纯几何

/// 面板定位几何 — 纯计算，不持有窗口与偏好对象
enum ClipboardPanelGeometry {

    /// 目标屏：主屏策略取原点屏，否则取鼠标所在屏（都取不到时回退主屏）
    static func targetScreen(position: ClipboardPanelPosition, mouse: NSPoint) -> NSScreen {
        let fallback = NSScreen.main ?? NSScreen.screens[0]
        if position == .primaryScreen {
            return NSScreen.screens.first { $0.frame.origin == .zero } ?? fallback
        }
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? fallback
    }

    /// 面板 frame：目标屏 visibleFrame 底部，宽 = width - 40（下限 420），底边距 12pt；
    /// 鼠标位置策略下贴到鼠标附近，并夹紧在可见区域内
    static func panelFrame(visible: NSRect, panelHeight: Double,
                           position: ClipboardPanelPosition, mouse: NSPoint) -> NSRect {
        let width = max(420, visible.width - 40)
        let height = min(CGFloat(panelHeight), visible.height / 3)
        var origin = NSPoint(x: visible.minX + 20, y: visible.minY + 12)
        if position == .mouseLocation {
            origin = NSPoint(x: min(max(mouse.x - width / 2, visible.minX + 10), visible.maxX - width - 10),
                             y: min(max(mouse.y - height - 10, visible.minY + 10), visible.maxY - height - 10))
        }
        return NSRect(x: origin.x, y: origin.y, width: width, height: height)
    }
}
