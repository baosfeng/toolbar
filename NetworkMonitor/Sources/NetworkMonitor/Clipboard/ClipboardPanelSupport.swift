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

// MARK: - 快捷键帮助键位

/// 快捷键帮助 — 面板「?」浮层展示的全部键位（纯数据，界面与读屏共用一份口径）
///
/// 顺序与面板实际按键拦截一致：直选 → 粘贴 → Paste Stack → 过滤 → 收藏 → 删除 → 收起 → 移动 → 设置。
enum ClipboardShortcutHelp {

    /// 一条键位：键帽 + 作用
    struct Entry: Equatable, Sendable {
        /// 键帽文字（如「⌘⇧⌫」）
        let keys: String
        /// 键位作用
        let action: String
    }

    /// 浮层标题（同时用作悬浮层的无障碍标签）
    static let title = "快捷键帮助"

    /// 全部键位（12 条，浮层按两列 × 6 行排布）
    static let entries: [Entry] = [
        Entry(keys: "⌘1–9", action: "快速粘贴第 N 条"),
        Entry(keys: "↵", action: "粘贴并收起"),
        Entry(keys: "⌥↵", action: "粘贴为纯文本"),
        Entry(keys: "⌘S", action: "加入 Paste Stack"),
        Entry(keys: "⌘⇧S", action: "清空 Paste Stack"),
        Entry(keys: "⇧Tab", action: "反向切换过滤"),
        Entry(keys: "⌘D", action: "收藏 / 取消收藏"),
        Entry(keys: "⌘⌫", action: "删除选中项"),
        Entry(keys: "⌘⇧⌫", action: "清空全部"),
        Entry(keys: "Esc", action: "收起面板"),
        Entry(keys: "← →", action: "切换条目"),
        Entry(keys: "⌘,", action: "打开剪贴板设置"),
    ]
}

// MARK: - 首次引导文案

/// 首次引导态文案 — 图标 + 两句话 + 三条快捷键胶囊
///
/// 与「没有匹配的剪贴板条目」空态的分工：空态解释「为什么没内容」，引导态解释「这里是什么、怎么用」，
/// 只在「未被引导过 + 历史为空」时出现（判定在面板控制器，标记写 ClipboardPreferences.hasGuidedClipboardAccess）。
enum ClipboardGuideText {
    /// 引导图标（SF Symbol）
    static let symbolName = "doc.on.clipboard"
    /// 第一句：说明会自动收录
    static let firstLine = "复制任意内容后，这里会自动收录"
    /// 第二句：说明怎么用
    static let secondLine = "选中一条即可粘贴回刚才的应用"
    /// 关闭按钮文案
    static let dismissTitle = "知道了"
    /// 唤起键未知时的回退文案（正常情况下由面板按偏好传入真实组合键）
    static let toggleFallbackText = "⌥⌘V"
    /// 唤起胶囊的作用文案
    static let toggleAction = "唤起面板"
}