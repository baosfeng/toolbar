import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - Token 页页名位的来源切换器

/// 来源切换器 —— 页头左侧「[全部 ▾]」，点开是来源清单
///
/// 为什么不用分段控件：来源数是 1…7 且会继续增长，页头 296pt 里再并排一个分段
/// 会把范围分段挤掉；下拉是恒定宽度的一行。
/// 为什么不用 NSPopUpButton：页头控件都是 MenuPanelRow（键盘可达 + 手型光标 + 按下缩放），
/// 换成 AppKit 下拉会让这一个控件在视觉与键盘行为上与邻居不一致。
///
/// 菜单只列「已启用且有数据」的来源（未安装的归设置页管）；当前来源带勾选态。
final class TokenSourceSelectorView: MenuPanelRow {

    /// 「全部」在菜单里的标识（来源 rawValue 不会撞上这个串）
    static let allIdentifier = "all"
    /// 页头里给它的宽度上限（超出即压缩，避免把范围分段挤走）
    static let maxWidth: CGFloat = 88

    /// 选中回调（nil = 全部）
    var onSelect: ((TokenSourceID?) -> Void)?

    private let titleLabel: NSTextField
    private(set) var current: TokenSourceID?
    /// 可选来源（顺序 = TokenSourceID.allCases，由调用方过滤）
    private(set) var options: [TokenSourceID] = []

    init() {
        // 首帧还不知道有哪些来源：先写「全部」，update 后按可用来源数改写
        titleLabel = MenuPanelLabel.text("全部",
                                         font: PaneCardStyle.cardTitleFont,
                                         color: PaneCardStyle.secondaryText)
        super.init(height: PaneCardStyle.pageHeadHeight)
        contentStack.spacing = 2
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        contentStack.addArrangedSubview(titleLabel)
        if let caret = MenuPanelLabel.symbol("chevron.down", pointSize: 8,
                                            color: PaneCardStyle.tertiaryText) {
            contentStack.addArrangedSubview(caret)
        }
        widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        onClick = { [weak self] in self?.presentMenu() }
        // 自绘控件必须自己声明是 AX 元素：行里的 NSTextField 会先被 AX 树收走，
        // 不声明时读屏与 nmcli 只看到一行「全部」文本、按不动它
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibilityLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: 数据

    /// 更新当前来源与可选清单（渲染每次都会调）
    func update(current: TokenSourceID?, options: [TokenSourceID]) {
        self.current = current
        self.options = options
        titleLabel.stringValue = Self.title(for: current, options: options)
        updateAccessibilityLabel()
    }

    /// 页名文案：只有一个可用来源时直接写它（此时「全部」等于它，写「全部」反而看不出在看什么）
    static func title(for source: TokenSourceID?, options: [TokenSourceID]) -> String {
        if let source { return source.displayName }
        return options.count == 1 ? (options.first?.displayName ?? "全部") : "全部"
    }

    // MARK: 菜单

    /// 弹出清单（鼠标点击 / 键盘 Enter / 读屏 AXPress 共用这一条路径）
    func presentMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if options.isEmpty {
            // 没有任何可用来源时也给一条可读的说明，而不是弹出一个空菜单
            let empty = NSMenuItem(title: "尚无可用来源（去设置页启用）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            // 「全部」只在两个以上可用来源时才出现（单源时它和那一项完全等价）
            if options.count > 1 {
                menu.addItem(item(for: nil))
                menu.addItem(.separator())
            }
            for source in options { menu.addItem(item(for: source)) }
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: bounds.height + 2),
                   in: self)
    }

    /// 单项：勾选态表示当前来源，标识走 representedObject（顺序可能变，不按下标还原）
    private func item(for source: TokenSourceID?) -> NSMenuItem {
        let item = NSMenuItem(title: Self.title(for: source, options: options),
                              action: #selector(pickSource(_:)),
                              keyEquivalent: "")
        item.target = self
        item.representedObject = source?.rawValue ?? Self.allIdentifier
        item.state = source == current ? .on : .off
        return item
    }

    @objc private func pickSource(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String
        onSelect?(raw.flatMap { $0 == Self.allIdentifier ? nil : TokenSourceID(rawValue: $0) })
    }

    // MARK: 无障碍

    private func updateAccessibilityLabel() {
        let name = Self.title(for: current, options: options)
        let hint = options.isEmpty ? "没有其他可选来源" : "可切换的来源 " + String(options.count) + " 个"
        setAccessibilityLabel("数据来源：" + name + "，点击切换（" + hint + "）")
        setAccessibilityHelp("弹出来源清单：全部 / 已启用且有数据的来源")
    }
}
