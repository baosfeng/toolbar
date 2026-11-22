import AppKit
import NetworkMonitorDesign

// MARK: - 二级页返回按钮

/// 二级页返回按钮（「返回额度」）—— 与 Token 页返回按钮同尺寸同底色
final class BillingDetailBackButton: NSButton {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        title = "额度"
        font = NSFont.systemFont(ofSize: 10, weight: .bold)
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = PaneCardStyle.secondaryText
        if let image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            self.image = image.withSymbolConfiguration(config) ?? image
            imagePosition = .imageLeading
        }
        setButtonType(.momentaryChange)
        setAccessibilityLabel("返回额度主表")
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        PaneCardStyle.bandFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }
}
