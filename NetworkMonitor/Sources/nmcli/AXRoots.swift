import ApplicationServices
import CoreGraphics

// MARK: - AX 遍历根集合

/// 一次查找要从哪些根开始遍历，以及顺序
///
/// 为什么不只从 `AXUIElementCreateApplication` 的 children 走：
/// 菜单豆面板是 `NSPanel`（非激活），**不在 AX 树里**——它只能靠「在面板 bounds 内做一次命中测试，
/// 再沿父链爬到 `AXPopover`」拿到。所以面板内容必须作为额外的根补进来，
/// 否则 `nmcli find/click/ax` 在面板上什么都找不到。
///
/// 顺序也是契约：状态项 → 面板 → 窗口 → 主菜单。
/// 状态项排第一是因为 `--role AXMenuBarItem --index 0` 要命中的是用户点的那个菜单豆，
/// 而不是主菜单里的 Apple / 应用名——那两项也在 AX 里、也是 AXMenuBarItem，
/// 且坐标恒为 0,33 的脏值，排在前面会把索引语义整个搅乱。
enum AXRoots {

    /// 该 app 的全部 AX 根（按遍历顺序）
    static func of(_ target: AppTarget) -> [AXUIElement] {
        var roots: [AXUIElement] = []
        if let extras = AXReader.attribute(target.axRoot, "AXExtrasMenuBar"),
           CFGetTypeID(extras) == AXUIElementGetTypeID() {
            roots.append(extras as! AXUIElement)
        }
        if let popover = PanelGeometry.popover(of: target) {
            roots.append(popover.element)
        }
        if let raw = AXReader.attribute(target.axRoot, kAXWindowsAttribute as String),
           let windows = raw as? [AXUIElement] {
            roots.append(contentsOf: windows)
        }
        if let menubar = AXReader.attribute(target.axRoot, kAXMenuBarAttribute as String),
           CFGetTypeID(menubar) == AXUIElementGetTypeID() {
            roots.append(menubar as! AXUIElement)
        }
        return roots
    }

    /// 从全部根里按条件收集（跨根去重：同一元素可能既在窗口里又在面板里）
    static func collect(_ target: AppTarget, maxDepth: Int = 16, maxNodes: Int = 4000,
                        match: (AXNode) -> Bool) -> [AXNode] {
        var hits: [AXNode] = []
        var seen: Set<CFHashCode> = []
        for root in of(target) {
            for node in AXReader.collect(from: root, maxDepth: maxDepth, maxNodes: maxNodes, match: match) {
                let hash = CFHash(node.element)
                guard !seen.contains(hash) else { continue }
                seen.insert(hash)
                hits.append(node)
            }
        }
        return hits
    }

    /// 遍历全部根（dump 用），跳过重复根
    static func walkAll(_ target: AppTarget, maxDepth: Int, maxNodes: Int, visit: (AXNode) -> Void) {
        var seen: Set<CFHashCode> = []
        for root in of(target) {
            let hash = CFHash(root)
            guard !seen.contains(hash) else { continue }
            seen.insert(hash)
            AXReader.walk(from: root, maxDepth: maxDepth, maxNodes: maxNodes, visit: visit)
        }
    }
}
