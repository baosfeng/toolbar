import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - AX 元素读写

/// 一个 AX 元素的快照：属性在构造时一次性读出，之后不再回查
///
/// 为什么要快照：AX 元素是指向目标进程对象的引用，每次读属性都是一次跨进程调用；
/// 遍历整棵树时逐属性回查会让一次 dump 从毫秒级涨到秒级，且中途元素可能已失效。
struct AXNode {
    let element: AXUIElement
    let role: String
    let title: String
    let desc: String
    let value: String
    let position: CGPoint?
    let size: CGSize?
    let actions: [String]
    let depth: Int

    /// 元素中心点（无坐标时为 nil）——点击回退与命中测试都用它
    var center: CGPoint? {
        guard let position, let size else { return nil }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    var frameDescription: String {
        guard let position, let size else { return "-" }
        return "\(Format.point(position)) \(Int(size.width))x\(Int(size.height))"
    }

    var describe: String {
        let indent = String(repeating: "  ", count: depth)
        var parts = [role.isEmpty ? "?" : role]
        if !title.isEmpty { parts.append("title=\(title)") }
        if !desc.isEmpty { parts.append("desc=\(desc)") }
        if !value.isEmpty { parts.append("value=\(value)") }
        parts.append(frameDescription)
        if !actions.isEmpty { parts.append("actions=[\(actions.joined(separator: ","))]") }
        return indent + parts.joined(separator: " ")
    }
}

enum AXReader {

    /// 读单个属性；不存在 / 类型不符都返回 nil（AX 报错是常态，不当作异常）
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String {
        guard let value = attribute(element, name) else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var raw = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &raw) else { return nil }
        return raw
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var raw = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &raw) else { return nil }
        return raw
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    /// 读一个元素的完整快照
    static func node(_ element: AXUIElement, depth: Int = 0) -> AXNode {
        AXNode(element: element,
               role: string(element, kAXRoleAttribute as String),
               title: string(element, kAXTitleAttribute as String),
               desc: string(element, kAXDescriptionAttribute as String),
               value: string(element, kAXValueAttribute as String),
               position: point(element, kAXPositionAttribute as String),
               size: size(element, kAXSizeAttribute as String),
               actions: actions(element),
               depth: depth)
    }

    /// 深度优先遍历（含根），超过 depth 或元素数上限即停
    ///
    /// 上限存在的理由：面板里滚动区可能有上千个静态文本，dump 全量既慢又会把终端刷爆。
    static func walk(from root: AXUIElement, maxDepth: Int = 12, maxNodes: Int = 1500,
                     visit: (AXNode) -> Void) {
        var budget = maxNodes
        func step(_ element: AXUIElement, _ depth: Int) {
            guard budget > 0 else { return }
            budget -= 1
            visit(node(element, depth: depth))
            guard depth < maxDepth else { return }
            for child in children(element) { step(child, depth + 1) }
        }
        step(root, 0)
    }

    /// 收集符合条件的元素（find / click 用），保持文档顺序
    static func collect(from root: AXUIElement, maxDepth: Int, maxNodes: Int = 4000,
                        match: (AXNode) -> Bool) -> [AXNode] {
        var hits: [AXNode] = []
        walk(from: root, maxDepth: maxDepth, maxNodes: maxNodes) { node in
            if match(node) { hits.append(node) }
        }
        return hits
    }

    /// 点命中测试：该坐标最上层的元素
    static func element(at point: CGPoint) -> AXNode? {
        var element: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        return node(element)
    }

    /// 沿父链向上找到第 n 个符合条件的祖先（找 AXPopover 这类容器用）
    static func ancestor(of element: AXUIElement, where match: (AXNode) -> Bool, limit: Int = 10) -> AXNode? {
        var current: AXUIElement? = element
        var steps = 0
        while let node = current, steps < limit {
            let snapshot = AXReader.node(node)
            if match(snapshot) { return snapshot }
            guard let parent = attribute(node, kAXParentAttribute as String), CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return nil
            }
            current = (parent as! AXUIElement)
            steps += 1
        }
        return nil
    }
}

// MARK: - 菜单栏

enum MenuBarReader {

    /// 菜单栏状态项（AXExtrasMenuBar 下的一级子元素，即 AXMenuExtra）
    ///
    /// 位置必须现读 `kAXPositionAttribute`：状态项宽度随上下行速率文字实时变化，
    /// 实测同一台机器出现过 x=1065 / 1075 / 1115 三个值，写死坐标必然失效。
    static func statusItems(of target: AppTarget) -> [AXNode] {
        let app = target.axRoot
        var items: [AXNode] = []
        for key in ["AXExtrasMenuBar", kAXMenuBarAttribute as String] {
            guard let raw = AXReader.attribute(app, key),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let bar = raw as! AXUIElement
            for child in AXReader.children(bar) {
                items.append(AXReader.node(child))
            }
        }
        return items
    }

    /// 主状态项：默认取 AXExtrasMenuBar 的第一个（一览只有一个状态项）
    static func primaryStatusItem(of target: AppTarget) -> AXNode? {
        statusItems(of: target).first { $0.role == "AXMenuBarItem" }
    }

    /// 菜单栏主菜单里的菜单项（「设置…」「退出 一览」等）
    static func appMenuItems(of target: AppTarget) -> [AXNode] {
        let app = target.axRoot
        guard let raw = AXReader.attribute(app, kAXMenuBarAttribute as String),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return [] }
        let bar = raw as! AXUIElement
        var items: [AXNode] = []
        for barItem in AXReader.children(bar) where AXReader.string(barItem, kAXTitleAttribute as String) == target.name {
            for menu in AXReader.children(barItem) {
                for item in AXReader.children(menu) {
                    items.append(AXReader.node(item))
                }
            }
        }
        return items
    }
}
