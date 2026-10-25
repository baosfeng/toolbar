import AppKit

// MARK: - 图标块

/// 28×28 圆角图标块（原型 tile：labelColor 6% 底 + 次要色符号）
final class ProviderIconTileView: NSView {

    private let icon: NSImageView?

    init(symbolName: String) {
        icon = MenuPanelLabel.symbol(symbolName, pointSize: 15, color: .secondaryLabelColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        if let icon {
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        layer?.backgroundColor = MenuPanelStyle.dynamicLabel(alpha: 0.06).cgColor
    }
}

// MARK: - 状态点

/// 状态点 — 绿=正常 / 已授权，橙=待授权 / 异常，灰=停用 / 未配置
final class ProviderStatusDotView: NSView {

    enum Kind: Equatable {
        case ok
        case warn
        case idle
    }

    var kind: Kind = .idle {
        didSet {
            guard kind != oldValue else { return }
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 6, height: 6) }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = switch kind {
        case .ok: .systemGreen
        case .warn: .systemOrange
        case .idle: .tertiaryLabelColor
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
