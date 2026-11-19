import AppKit
import NetworkMonitorUI

// MARK: - 面板分页枚举

/// 面板分页（顺序即数字键 1...N 与 ←/→ 循环顺序）
///
/// **rawValue 是显式写死的**（不是声明位置）：它进过旧偏好的 Int 顺序键
/// （`panel.tabs.order` / `panel.tabs.visible`），删 / 插一个 case 就会让后面的编号
/// 整体前移、老用户的顺序静默错位。新增分页一律取当前未占用的最大编号 +1；
/// 下线分页时保留它的编号空着（见 `PanelTabCatalog.legacyRawValueToStableID`）。
///
/// 剪贴板分页已下线（编号 1 空置）：历史剪贴板只在屏幕底部的独立浮层面板展示，
/// 菜单面板不再重复一份；入口改为标题栏齿轮菜单的「剪贴板历史…」。
enum MenuPanelTab: Int, CaseIterable {
    case network = 0
    case transfer = 2
    case credits = 3
    case token = 4
    case system = 5

    /// 本分页的描述符 —— 文案 / 图标 / 快照后缀 / 取证标识的唯一来源（见 `PaneModuleCatalog`）
    ///
    /// 改造前这里是三个穷尽 switch（title / stableID / symbolName）：加一个分页要改三处，
    /// 漏一处没有编译错误，只会静默用错图标或存错偏好 id。现在描述符目录是唯一真源，
    /// 枚举只负责编号（rawValue 冻结，见 `PanelTabCatalog.legacyRawValueToStableID`）。
    var descriptor: PaneModuleDescriptor {
        if let descriptor = PaneModuleCatalog.descriptor(forRawValue: rawValue) {
            return descriptor
        }
        // 目录漏登记：开发期断言 + 兜底值（不静默套用别的分页文案，也不崩 release）
        assertionFailure("分页 \(self) 未在 PaneModuleCatalog 登记")
        return PaneModuleDescriptor.placeholder(rawValue: rawValue)
    }

    /// 分段标签标题
    var title: String { descriptor.title }

    /// 稳定 id —— 顺序偏好里存的就是它
    ///
    /// 不用 `rawValue`：那是 Int（编号），将来再下线一个分页时编号仍会变；
    /// 稳定 id 与 `PanelTabCatalog.stableIDs` 同源（自洽性由 TestRunner 断言）。
    var stableID: String { descriptor.id }

    /// 分段标签图标（SF Symbols，禁止 emoji）
    var symbolName: String { descriptor.symbolName }
}

// MARK: - 顶部细分段

/// 顶部细分段控件 — 自绘 NSView（非 NSSegmentedControl 默认样式）
///
/// 交互：点击切换、`←/→` 由面板根视图统一转发（见 `MenuPanelView.keyDown`）、
/// 选中态用强调色文字 + 略深的滑块背景，非选中态用次要文字色，深浅色自适应。
final class MenuTabBarView: NSView {

    /// 高度（设计稿 28）
    static let barHeight: CGFloat = 28

    /// 选中项变化回调
    var onSelect: ((MenuPanelTab) -> Void)?

    /// 当前选中项
    var selected: MenuPanelTab = .network {
        didSet {
            guard selected != oldValue else { return }
            needsDisplay = true
            setAccessibilityChildren(accessibilitySegmentElements())
        }
    }

    /// 可见分页（由 PanelTabPreferences 驱动；默认全量）
    ///
    /// 设置页在面板显示期间改可见性时由面板根视图重设，这里同步重绘并按新分段重建读屏元素，
    /// 否则仍按旧段数绘制、点击命中也会错位。
    var visibleTabs: [MenuPanelTab] = MenuPanelTab.allCases {
        didSet {
            guard visibleTabs != oldValue else { return }
            hoveredIndex = nil
            needsDisplay = true
            setAccessibilityChildren(accessibilitySegmentElements())
        }
    }

    private var hoveredIndex: Int?

    private var trackingAreaRef: NSTrackingArea?

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: Self.barHeight)])
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("面板分页")
        // 六个分段全是自绘（draw + mouseDown 算 x 坐标），对辅助技术来说原本整条是空白：
        // 只有一个「面板分页」组，听不出当前选中哪页，也没有任何切页方式。
        // 这里补一组虚拟子元素：每段一个按钮，带「已选中」值，激活即切页。
        setAccessibilityChildren(accessibilitySegmentElements())
    }

    /// 每个分段一个可激活的虚拟元素（不自绘子视图，避免改动现有绘制与命中逻辑）
    private func accessibilitySegmentElements() -> [NSAccessibilityElement] {
        let segmentWidth = bounds.width / CGFloat(visibleTabs.count)
        return visibleTabs.enumerated().map { index, tab in
            let element = MenuTabSegmentElement(onPress: { [weak self] in self?.activateSegment(at: index) })
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityTitle(tab.title)
            element.setAccessibilityValue(tab == selected ? "已选中" : "")
            element.setAccessibilityFrame(NSRect(x: CGFloat(index) * segmentWidth, y: 0,
                                                 width: segmentWidth, height: bounds.height))
            element.setAccessibilityIdentifier("panel-tab-\(tab.rawValue)")
            return element
        }
    }

    /// 切到指定分段（读屏激活 / 鼠标点击共用同一个入口）
    func activateSegment(at index: Int) {
        select(index: index)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        MenuPanelStyle.subtleFill.setFill()
        track.fill()
        NSColor.separatorColor.setStroke()
        track.lineWidth = 1
        track.stroke()

        let segmentWidth = bounds.width / CGFloat(visibleTabs.count)
        for (index, tab) in visibleTabs.enumerated() {
            let segmentRect = NSRect(x: CGFloat(index) * segmentWidth + 2, y: 2,
                                     width: segmentWidth - 4, height: bounds.height - 4)
            let isSelected = tab == selected

            if isSelected || hoveredIndex == index {
                let fill = isSelected
                    ? MenuPanelStyle.dynamicLabel(alpha: 0.14)
                    : MenuPanelStyle.dynamicLabel(alpha: 0.06)
                fill.setFill()
                NSBezierPath(roundedRect: segmentRect, xRadius: 6, yRadius: 6).fill()
            }

            drawContent(tab: tab, in: segmentRect, isSelected: isSelected)
        }
    }

    /// 分段内容布局：字体、图标尺寸、间距、标题宽度
    ///
    /// 六段后每段 44pt（264 / 6）、可用 37pt（再扣分段内边距）：
    /// 「系统」两字 11pt 实测 21.87pt，带 10pt 图标总宽 34.87pt，完整不截断；
    /// 「剪贴板」「Token」等长标签会越界，先把图标按剩余宽度压缩，
    /// 压到 5pt 以下已不可辨认时干脆隐藏图标、只留居中文字（避免「残影」），
    /// 仍不够时退到 10pt 字号。返回的 titleSize 为最终字体下的测量值。
    private func layout(tab: MenuPanelTab,
                        isSelected: Bool,
                        availableWidth: CGFloat) -> (font: NSFont, iconSize: CGFloat, gap: CGFloat, titleSize: NSSize) {
        var font = isSelected
            ? NSFont.systemFont(ofSize: 11, weight: .semibold)
            : NSFont.systemFont(ofSize: 11, weight: .regular)
        let title = tab.title as NSString
        var titleSize = title.size(withAttributes: [.font: font])
        var iconSize: CGFloat = 10
        var gap: CGFloat = 3
        var contentWidth = iconSize + gap + titleSize.width
        if contentWidth > availableWidth {
            let squeezed = max(0, availableWidth - titleSize.width - 2)
            // 5pt 以下的图标已不可辨认，隐藏它让文字居中，仍完整可读
            iconSize = squeezed >= 5 ? squeezed : 0
            gap = iconSize > 0 ? 2 : 0
            contentWidth = iconSize + gap + titleSize.width
        }
        if contentWidth > availableWidth {
            font = isSelected
                ? NSFont.systemFont(ofSize: 10, weight: .semibold)
                : NSFont.systemFont(ofSize: 10, weight: .regular)
            titleSize = title.size(withAttributes: [.font: font])
        }
        return (font, iconSize, gap, titleSize)
    }

    /// 绘制单个分段：图标 + 文字整体居中
    private func drawContent(tab: MenuPanelTab, in rect: NSRect, isSelected: Bool) {
        // 未选中态用 62% labelColor：secondaryLabelColor 在不透明底色上实测 ~4.5:1 临界，
        // 62% 混合灰在浅/深色下都能稳定 ≥4.5:1
        let color = isSelected ? MenuPanelStyle.accentColor : MenuPanelStyle.tertiaryText
        let metrics = layout(tab: tab, isSelected: isSelected, availableWidth: max(0, rect.width - 3))
        let attributes: [NSAttributedString.Key: Any] = [.font: metrics.font, .foregroundColor: color]
        let startX = rect.midX - (metrics.iconSize + metrics.gap + metrics.titleSize.width) / 2

        if metrics.iconSize > 0, let icon = tabIcon(tab, color: color) {
            let iconRect = NSRect(x: startX, y: rect.midY - metrics.iconSize / 2,
                                  width: metrics.iconSize, height: metrics.iconSize)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        }
        let textY = rect.midY - metrics.titleSize.height / 2
        (tab.title as NSString).draw(at: NSPoint(x: startX + metrics.iconSize + metrics.gap, y: textY),
                                     withAttributes: attributes)
    }

#if DEBUG
    /// 快照自证专用：各段标题在各自可用宽度下的实测内容宽度（pt）
    static func segmentMetrics() -> [(title: String, content: CGFloat, available: CGFloat)] {
        let barWidth = MenuPanelStyle.contentWidth - 32
        let segmentWidth = barWidth / CGFloat(MenuPanelTab.allCases.count)
        let available = segmentWidth - 3
        let probe = MenuTabBarView()
        return MenuPanelTab.allCases.map { tab in
            let metrics = probe.layout(tab: tab, isSelected: true, availableWidth: available)
            return (tab.title, metrics.iconSize + metrics.gap + metrics.titleSize.width, available)
        }
    }
#endif

    /// 生成着色后的 SF Symbol（palette 配置直接决定颜色，避免模板色歧义）
    private func tabIcon(_ tab: MenuPanelTab, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title) else {
            return nil
        }
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(sizeConfig.applying(colorConfig)) ?? base
    }

    // MARK: - 交互

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
        NSCursor.arrow.set()
    }

    private func updateHover(at point: NSPoint) {
        guard bounds.contains(point) else {
            hoveredIndex = nil
            needsDisplay = true
            return
        }
        let index = Int(point.x / (bounds.width / CGFloat(visibleTabs.count)))
        hoveredIndex = max(0, min(visibleTabs.count - 1, index))
        needsDisplay = true
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let index = Int(point.x / (bounds.width / CGFloat(visibleTabs.count)))
        select(index: index)
    }

    /// 选中指定下标（越界忽略）
    func select(index: Int) {
        guard index >= 0, index < visibleTabs.count else { return }
        let tab = visibleTabs[index]
        selected = tab
        onSelect?(tab)
    }
}

// MARK: - 分段的可激活虚拟元素

/// 自绘分段的读屏元素：NSAccessibilityElement 本身不能点，这里把激活转发给分段条
private final class MenuTabSegmentElement: NSAccessibilityElement {
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}