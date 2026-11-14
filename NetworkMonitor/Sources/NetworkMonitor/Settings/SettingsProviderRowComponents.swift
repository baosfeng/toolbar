import AppKit

// MARK: - 图标块

/// 28×28 圆角图标块（原型 tile：浅一档的面色底 + 次级色符号）
///
/// 底取主题 `selectedFill`（「面」上浅一档的角色），符号取 `textSecondary`：
/// 原来写的是「labelColor 6%」——系统色通道，不随三套主题变。
final class ProviderIconTileView: NSView {

    private let icon: NSImageView?

    init(symbolName: String) {
        icon = MenuPanelLabel.symbol(symbolName, pointSize: 15, color: SettingsTheme.textSecondary)
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
        layer?.backgroundColor = SettingsTheme.selectedFill.cgColor
    }
}

// MARK: - 状态点

/// 状态点 — 达标（okInk）/ 告警（warnInk）/ 中性停用（ghost）
///
/// 颜色在 `draw` 里现取：主题换的是「角色 → 色值」映射，视图收不到外观回调，
/// 存成 CGColor 会停在旧主题色。
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
        case .ok: SettingsTheme.okInk
        case .warn: SettingsTheme.warnInk
        case .idle: SettingsTheme.ghost
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
