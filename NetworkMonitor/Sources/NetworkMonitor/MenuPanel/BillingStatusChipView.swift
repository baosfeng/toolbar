import AppKit

// MARK: - 状态胶囊（取代 5pt 圆点）

/// provider 状态胶囊 —— 正常 / 限流 / 出错 / 查询中
///
/// 取代旧实现的 5pt 圆点（圆点在 320pt 浮层里既难辨认、也无法表达四种状态）。
/// 胶囊用墨色文字（不是原色）：9.5pt 小字压彩色底需要 ≥4.5:1，原色只有 3–4:1。
final class BillingStatusChipView: NSView {

    enum Kind {
        /// 正常
        case ok
        /// 已限流 / 额度告警
        case warn
        /// 请求失败
        case error
        /// 查询中
        case loading
        /// 无数据
        case idle
    }

    private let label = MenuPanelLabel.text("", font: PaneCardStyle.chipFont,
                                            color: PaneCardStyle.tertiaryText)
    private var kind: Kind = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 15),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + 12, height: 15)
    }

    /// 更新状态与文案（文案由调用方给，语义色由 kind 定）
    func update(kind: Kind, text: String) {
        self.kind = kind
        label.stringValue = text
        label.textColor = inkColor
        setAccessibilityLabel(text)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// 文字墨色（小字必须过 4.5:1，故一律用 ink 档而不是原色）
    private var inkColor: NSColor {
        switch kind {
        case .ok: return PaneCardStyle.okInk
        case .warn: return PaneCardStyle.warnInk
        case .error: return PaneCardStyle.requestInk
        case .loading, .idle: return PaneCardStyle.tertiaryText
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        PaneCardStyle.bandFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        super.draw(dirtyRect)
    }
}
