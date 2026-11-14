import AppKit
import NetworkMonitorCore

// MARK: - 卡片缩略图

/// 卡片缩略图 — 就绪后 0.2s 淡入占位符号之上
///
/// 绘制走 `ClipboardCardView.drawAspectFill(image:in:)`（与既有图片卡同一口径：等比填充裁剪，
/// 不留白、不变形），本视图只负责「画真图 + 圆角裁切 + 淡入」。
@MainActor
final class ClipboardCardThumbnailView: NSView {

    /// 缩略图（nil 时不绘制）
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// 纯装饰层：鼠标事件穿透到卡片本体
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        ClipboardCardView.drawAspectFill(image: image, in: bounds)
    }
}
