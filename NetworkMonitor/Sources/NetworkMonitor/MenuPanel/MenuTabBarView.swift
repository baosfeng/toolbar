import AppKit

// MARK: - 面板分页枚举

/// 面板四个分页
enum MenuPanelTab: Int, CaseIterable {
    case network
    case clipboard
    case transfer
    case credits
    case token

    /// 分段标签标题
    var title: String {
        switch self {
        case .network: return "网络"
        case .clipboard: return "剪贴板"
        case .transfer: return "传送"
        case .credits: return "额度"
        case .token: return "Token"
        }
    }

    /// 分段标签图标（SF Symbols，禁止 emoji）
    var symbolName: String {
        switch self {
        case .network: return "network"
        case .clipboard: return "doc.on.clipboard"
        case .transfer: return "paperplane"
        case .credits: return "creditcard"
        case .token: return "chart.bar.xaxis"
        }
    }
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

        let segmentWidth = bounds.width / CGFloat(MenuPanelTab.allCases.count)
        for (index, tab) in MenuPanelTab.allCases.enumerated() {
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
    /// 五段后每段约 52.8pt（264 / 5），12pt 字 + 12pt 图标的「剪贴板」会越界：
    /// 统一降到 11pt 字 / 10pt 图标 / 3pt 间距，再按可用宽度把图标与间距压到 0，
    /// 仍不够时退一级字号。返回的 titleSize 为最终字体下的测量值。
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
            iconSize = max(0, availableWidth - titleSize.width - 2)
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
    /// 快照自证专用：五段标题在各自可用宽度下的实测内容宽度（pt）
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
        let index = Int(point.x / (bounds.width / CGFloat(MenuPanelTab.allCases.count)))
        hoveredIndex = max(0, min(MenuPanelTab.allCases.count - 1, index))
        needsDisplay = true
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let index = Int(point.x / (bounds.width / CGFloat(MenuPanelTab.allCases.count)))
        select(index: index)
    }

    /// 选中指定下标（越界忽略）
    func select(index: Int) {
        guard index >= 0, index < MenuPanelTab.allCases.count else { return }
        guard let tab = MenuPanelTab(rawValue: index) else { return }
        selected = tab
        onSelect?(tab)
    }
}