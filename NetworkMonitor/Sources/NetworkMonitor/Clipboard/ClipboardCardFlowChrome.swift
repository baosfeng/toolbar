import AppKit

// MARK: - 卡片流容器与空态（从 ClipboardCardFlowView 拆出，守住单文件体积上限）

/// 卡片流容器 — 翻转坐标系，让内容从顶部开始排布
///
/// internal 而非 private：由拆出的主文件 `ClipboardCardFlowView.swift` 跨文件实例化，
/// 同目录内无其他调用方。
final class ClipboardCardFlowContainer: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 空态视图

/// 空态视图 — 居中一句话 + 轻量 SF Symbol 图形（禁止 emoji）
///
/// internal 原因同上。
@MainActor
final class ClipboardEmptyStateView: NSView {

    private let message: String
    private let symbolName = "doc.on.clipboard"
    private let iconSize: CGFloat = 24
    private let iconGap: CGFloat = 10

    init(message: String) {
        self.message = message
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let text = message as NSString
        let textSize = text.size(withAttributes: attributes)
        let totalHeight = iconSize + iconGap + textSize.height
        let top = max(0, (bounds.height - totalHeight) / 2)

        let configuration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.tertiaryLabelColor]))
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .draw(in: NSRect(x: bounds.midX - iconSize / 2, y: top, width: iconSize, height: iconSize))
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: top + iconSize + iconGap),
                  withAttributes: attributes)
    }
}
