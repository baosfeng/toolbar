import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 筛选芯片行视图（搜索行内的类型 / 来源 App / 日期芯片）

/// 芯片行 —— 排在搜索框左侧，可叠加、可单个删除，右侧跟一个「＋筛选」按钮
///
/// 分工：矩形分配在 `ClipboardFilterChipRow`（纯函数，TestRunner 覆盖），本视图只做三件事 ——
/// 按字体量出每枚芯片的宽、照排好的矩形自绘、把点按翻译成「删哪一枚」。
/// 自绘而不为每枚芯片建子视图：芯片数量随筛选变化，建了就要删，而一行芯片的绘制成本不到一次布局。
@MainActor
final class ClipboardFilterChipRowView: NSView {

    /// 芯片被点掉（参数为芯片的 kind+value 标识）
    var onRemove: ((String) -> Void)?
    /// 「＋筛选」被点（由面板视图弹候选菜单）
    var onRequestMenu: ((NSRect) -> Void)?

    /// 当前芯片（顺序即显示顺序）
    private(set) var tokens: [ClipboardFilterToken] = []
    /// 最近一次排版的矩形（键为芯片标识）
    private var placedFrames: [String: CGRect] = [:]
    /// 最近一次排版里「+N」徽标的矩形（nil = 没有省略）
    private var overflowFrame: CGRect?
    /// 「＋筛选」按钮矩形
    private var menuFrame: CGRect = .zero

    /// 芯片字号（12pt：工具条里 24pt 控件统一档）
    private static let chipFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// 芯片底色（比工具条再深一档，与搜索框同族的凹陷感）
    private static let chipFill = NSColor.labelColor.withAlphaComponent(0.09)
    /// 芯片文字色
    private static let chipText = NSColor.labelColor.withAlphaComponent(0.85)

    override var isFlipped: Bool { true }

    /// 换成另一组芯片（面板视图是唯一调用方）
    func update(tokens: [ClipboardFilterToken]) {
        self.tokens = tokens
        needsDisplay = true
        needsLayout = true
    }

    /// 只有芯片与按钮处吃鼠标：本视图铺满工具条，其余位置一律放行，不挡搜索框与采集按钮
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, tokenID(at: point) != nil || menuFrame.contains(point) else { return nil }
        return self
    }

    // MARK: 排版与命中

    /// 按字体量出每枚芯片的宽，交给纯函数排版
    func layoutChips() -> [ClipboardFilterChipRow.Chip] {
        tokens.map { token in
            ClipboardFilterChipRow.Chip(id: token.id, label: token.label,
                                        width: Self.chipWidth(for: token.label))
        }
    }

    /// 一枚芯片的宽 = 文字宽 + 左右内边距 + 删除叉占位
    static func chipWidth(for label: String) -> CGFloat {
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: chipFont]).width)
        return textWidth + ClipboardFilterChipRow.chipPaddingX * 2 + ClipboardFilterChipRow.removeGlyphWidth
    }

    /// 落排版结果：矩形按标识存起来，绘制与命中都读它
    func apply(_ metrics: ClipboardFilterChipRow.Metrics) {
        let frames = Dictionary(uniqueKeysWithValues: metrics.chips.map { ($0.id, $0.frame) })
        guard frames != placedFrames || metrics.overflow?.frame != overflowFrame
                || metrics.menuButton != menuFrame else { return }
        placedFrames = frames
        overflowFrame = metrics.overflow?.frame
        menuFrame = metrics.menuButton
        needsDisplay = true
    }

    /// 命中的芯片标识（点删除叉或芯片本体都算删）
    func tokenID(at point: NSPoint) -> String? {
        placedFrames.first { $0.value.contains(point) }?.key
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = tokenID(at: point) { onRemove?(id); return }
        if menuFrame.contains(point) { onRequestMenu?(menuFrame); return }
        super.mouseDown(with: event)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        for token in tokens {
            guard let frame = placedFrames[token.id] else { continue }
            drawChip(label: token.label, in: frame)
        }
        if let overflowFrame, let overflowLabel = overflowLabel {
            drawChip(label: overflowLabel, in: overflowFrame, showsRemove: false)
        }
        drawMenuButton()
    }

    /// 「+N」徽标文案（只在有芯片被省略时出现）
    private var overflowLabel: String? {
        let dropped = tokens.count - placedFrames.count
        return dropped > 0 ? "+\(dropped)" : nil
    }

    private func drawChip(label: String, in frame: CGRect, showsRemove: Bool = true) {
        Self.chipFill.setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.chipFont, .foregroundColor: Self.chipText]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let textX = frame.minX + ClipboardFilterChipRow.chipPaddingX
        (label as NSString).draw(at: NSPoint(x: textX, y: frame.midY - textSize.height / 2), withAttributes: attributes)
        guard showsRemove else { return }
        // 删除叉：两笔斜线，不引 SF Symbol（芯片太小，符号细节糊成一团）
        let glyph = NSBezierPath()
        let cx = frame.maxX - ClipboardFilterChipRow.chipPaddingX - ClipboardFilterChipRow.removeGlyphWidth / 2
        glyph.move(to: NSPoint(x: cx - 3, y: frame.midY - 3))
        glyph.line(to: NSPoint(x: cx + 3, y: frame.midY + 3))
        glyph.move(to: NSPoint(x: cx + 3, y: frame.midY - 3))
        glyph.line(to: NSPoint(x: cx - 3, y: frame.midY + 3))
        glyph.lineWidth = 1
        Self.chipText.withAlphaComponent(0.7).setStroke()
        glyph.stroke()
    }

    /// 「＋筛选」：一枚描边胶囊里的加号，与芯片同高但更克制（不加底色）
    private func drawMenuButton() {
        guard menuFrame.width > 0 else { return }
        let stroke = NSColor.labelColor.withAlphaComponent(0.28)
        let path = NSBezierPath(roundedRect: menuFrame.insetBy(dx: 0.5, dy: 2), xRadius: 7, yRadius: 7)
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        let plus = NSBezierPath()
        let cx = menuFrame.midX - 3, cy = menuFrame.midY
        plus.move(to: NSPoint(x: cx, y: cy - 4))
        plus.line(to: NSPoint(x: cx, y: cy + 4))
        plus.move(to: NSPoint(x: cx - 4, y: cy))
        plus.line(to: NSPoint(x: cx + 4, y: cy))
        plus.lineWidth = 1.2
        stroke.setStroke()
        plus.stroke()
    }

    // MARK: 无障碍

    /// 每枚芯片一个可按下元素：读屏念「来源 App：Safari，移除来源 App 筛选」
    override func accessibilityChildren() -> [Any]? {
        tokens.compactMap { token in
            guard let frame = placedFrames[token.id] else { return nil }
            let element = DrawnAccessibilityReporter.element(
                role: .button,
                label: token.kind.menuTitle + "：" + token.label,
                parent: self) { [weak self] in self?.onRemove?(token.id) }
            element.setAccessibilityHelp(token.accessibilityHint)
            element.setAccessibilityFrame(DrawnAccessibilityReporter.screenFrame(of: frame, in: self))
            return element
        }
    }

    /// 整行作为一个组上报：读屏先念「筛选：3 项」，再逐枚展开
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        tokens.isEmpty ? "筛选：无" : "筛选：" + tokens.map(\.label).joined(separator: "、")
    }

    /// 组本身不可按下（能按的是里面每枚芯片）
    override func accessibilityPerformPress() -> Bool { false }
}
