import AppKit

// MARK: - 二级页返回按钮（‹ Token）

/// 二级页返回按钮（‹ Token，胶囊底色 + 左侧 chevron）
final class TokenDetailBackButton: NSButton {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        title = "Token"
        font = NSFont.systemFont(ofSize: 10, weight: .bold)
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = TokenPaneStyle.secondaryText
        if let image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            self.image = image.withSymbolConfiguration(config) ?? image
            imagePosition = .imageLeading
        }
        setButtonType(.momentaryChange)
        setAccessibilityLabel("返回 Token 主面板")
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.rowAltFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }
}
