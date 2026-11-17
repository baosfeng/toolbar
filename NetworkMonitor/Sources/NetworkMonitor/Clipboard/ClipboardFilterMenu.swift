import AppKit
import NetworkMonitorUI

// MARK: - 「＋筛选」候选菜单

/// 筛选候选菜单 —— 类型 / 来源 App / 日期三组，点一项即在芯片行增删一枚芯片
///
/// 为什么不沿用 NSSegmentedControl：类型只是三类筛选中的一类，来源与日期是开放式取值，
/// 分段控件的「固定槽位」形状表达不了「可叠加、可单个删除」。
/// 菜单项的 representedObject 存芯片标识（`ClipboardFilterToken.id`），动作侧按它还原芯片，
/// 不依赖菜单项顺序 —— 候选清单随条目实时变化，顺序不稳定。
@MainActor
enum ClipboardFilterMenu {

    /// 清除全部已选芯片的菜单项标识（正常芯片标识一定带冒号，不会撞上）
    static let clearAllID = "clear-all"

    /// 造菜单
    ///
    /// - Parameters:
    ///   - tokens: 当前已选芯片（决定各项勾选态与「清除全部」是否出现）
    ///   - sources: 来源 App 候选（调用方从当前条目聚合，见 `ClipboardSourceCatalog`）
    ///   - target: 菜单项动作的接收者
    ///   - action: 菜单项动作（参数为 NSMenuItem，见 `toggleFilterToken`）
    static func make(tokens: [ClipboardFilterToken],
                     sources: [ClipboardSourceCatalog.Source],
                     target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        append(to: menu, title: ClipboardFilterTokenKind.type.menuTitle,
               items: ClipboardFilter.allCases.filter(\.isChip).map { ClipboardFilterToken.type($0) },
               tokens: tokens, target: target, action: action)
        append(to: menu, title: ClipboardFilterTokenKind.source.menuTitle,
               items: sources.map { ClipboardFilterToken.source($0.name) },
               tokens: tokens, target: target, action: action)
        append(to: menu, title: ClipboardFilterTokenKind.date.menuTitle,
               items: ClipboardDateRange.allCases.map { ClipboardFilterToken.date($0) },
               tokens: tokens, target: target, action: action)
        if !tokens.isEmpty {
            menu.addItem(.separator())
            menu.addItem(item(title: "清除全部筛选", token: nil, checked: false,
                              target: target, action: action, identifier: clearAllID))
        }
        return menu
    }

    /// 由菜单项还原芯片（清除全部项返回 nil）
    static func token(from item: NSMenuItem) -> ClipboardFilterToken? {
        guard let identifier = item.representedObject as? String,
              identifier != clearAllID, let separator = identifier.firstIndex(of: ":") else { return nil }
        let kindRaw = String(identifier[identifier.startIndex..<separator])
        guard let kind = ClipboardFilterTokenKind(rawValue: kindRaw) else { return nil }
        return ClipboardFilterToken(kind: kind, value: String(identifier[identifier.index(after: separator)...]))
    }

    // MARK: 内部

    /// 追加一组：组标题 + 各项（勾选态按当前已选芯片）
    private static func append(to menu: NSMenu, title: String, items: [ClipboardFilterToken],
                               tokens: [ClipboardFilterToken], target: AnyObject, action: Selector) {
        guard !items.isEmpty else { return }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for token in items {
            menu.addItem(item(title: token.label, token: token, checked: tokens.contains(token),
                              target: target, action: action, identifier: token.id))
        }
    }

    /// 一项：标题 + 勾选态 + 标识
    private static func item(title: String, token: ClipboardFilterToken?, checked: Bool,
                             target: AnyObject, action: Selector, identifier: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = identifier
        item.state = checked ? .on : .off
        item.toolTip = token?.accessibilityHint
        return item
    }
}
