import AppKit

// MARK: - 栈角标

/// 卡片右上角的 Paste Stack 角标（①②③…）
///
/// 独立成视图的唯一理由：栈粘贴推进时要让它做一次弹入（`MotionKit.popIn`），
/// 画在内容层里就没法单独动。文案与编号口径沿用 `ClipboardCardView.badgeText(_:)`。
@MainActor
final class ClipboardCardStackBadgeView: NSView {

    /// 角标编号（0 = 不显示）
    private(set) var position = 0
    /// 内边距
    private static let horizontalInset: CGFloat = 4
    /// 字号
    private static let fontSize: CGFloat = 11

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    /// 纯装饰层：鼠标事件穿透到卡片本体
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 更新编号（0 隐藏）；编号变大说明栈在推进，返回是否需要弹入
    @discardableResult
    func update(position: Int) -> Bool {
        let advanced = position != 0 && position != self.position
        self.position = position
        isHidden = position == 0
        invalidateIntrinsicContentSize()
        needsDisplay = true
        if position != 0 { setAccessibilityLabel("Paste Stack 第 \(position) 项") }
        return advanced
    }

    override var intrinsicContentSize: NSSize {
        let size = textSize
        return NSSize(width: size.width + Self.horizontalInset * 2, height: size.height + 2)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: Self.fontSize, weight: .semibold),
         .foregroundColor: NSColor.white]
    }

    private var textSize: NSSize {
        guard position > 0 else { return .zero }
        return (ClipboardCardView.badgeText(position) as NSString).size(withAttributes: textAttributes)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard position > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let text = ClipboardCardView.badgeText(position) as NSString
        let size = text.size(withAttributes: textAttributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                  withAttributes: textAttributes)
    }
}
