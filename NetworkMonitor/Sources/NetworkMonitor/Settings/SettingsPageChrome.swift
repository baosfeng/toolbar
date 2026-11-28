import AppKit

// MARK: - 页头图标 / 分组标记（设置页的视觉锚点）

/// 页头左侧的图标徽章 —— 26pt 圆角方块 + SF Symbol
///
/// 为什么自绘底色而不是 `layer.backgroundColor`：强调色是动态 `NSColor`（换主题要重解析），
/// 存成 `CGColor` 会残留旧主题色——设置页换主题后「只有这一小块不变」是已知坑。
final class SettingsPageIconView: NSView {

    init(symbolName: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        imageView.contentTintColor = SettingsTheme.accent
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        SettingsTheme.accent.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7.5, yRadius: 7.5).fill()
    }
}

/// 分组标题前的强调竖条 —— 3×11 圆角，比「再加一级字号」更省空间
final class SettingsGroupMarker: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 3),
            heightAnchor.constraint(equalToConstant: 11),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        SettingsTheme.accent.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
