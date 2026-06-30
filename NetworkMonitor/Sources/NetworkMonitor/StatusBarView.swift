import AppKit

// MARK: - Status Bar View

/// 菜单栏自定义视图 — 垂直双栏，极致紧凑，自适应最宽文本
///
/// 布局：
///   ┌────────────┐
///   │↓ 1.2 MB/s  │  ← 绿色下行
///   │─────────── │  ← 细分隔线
///   │↑ 340 KB/s  │  ← 橙色上行
///   └────────────┘
@MainActor
final class StatusBarView: NSView {
    // 下行
    private let downIconView = NSImageView()
    private let downLabel = NSTextField(labelWithString: "0 B/s")

    // 上行
    private let upIconView = NSImageView()
    private let upLabel = NSTextField(labelWithString: "0 B/s")

    // 分割线
    private let divider = NSBox()

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private let iconSize: CGFloat = 9
    private let pad: CGFloat = 4  // 两边最小留白

    override var intrinsicContentSize: NSSize {
        // 取上下行中最宽的文字作为宽度基准
        let ds = downLabel.stringValue as NSString
        let us = upLabel.stringValue as NSString
        let w1 = ds.size(withAttributes: [.font: font]).width
        let w2 = us.size(withAttributes: [.font: font]).width
        let textWidth = ceil(max(w1, w2))
        let totalWidth = pad + iconSize + 2 + textWidth + pad
        let lineHeight = ceil(font.leading + font.capHeight + font.descender + 1)
        return NSSize(width: totalWidth, height: lineHeight * 2 + 1 + 4)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)

        // ── 下行图标 ──
        if let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "下行") {
            downIconView.image = img
            downIconView.contentTintColor = .systemGreen
            downIconView.symbolConfiguration = config
        }
        downIconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(downIconView)

        // ── 下行标签 ──
        downLabel.font = font
        downLabel.textColor = .systemGreen
        downLabel.alignment = .left
        downLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        downLabel.isBezeled = false
        downLabel.isEditable = false
        downLabel.drawsBackground = false
        downLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(downLabel)

        // ── 分割线 ──
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        // ── 上行图标 ──
        if let img = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "上行") {
            upIconView.image = img
            upIconView.contentTintColor = .systemOrange
            upIconView.symbolConfiguration = config
        }
        upIconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(upIconView)

        // ── 上行标签 ──
        upLabel.font = font
        upLabel.textColor = .systemOrange
        upLabel.alignment = .left
        upLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        upLabel.isBezeled = false
        upLabel.isEditable = false
        upLabel.drawsBackground = false
        upLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(upLabel)

        NSLayoutConstraint.activate([
            // 第一行：下行
            downIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            downIconView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            downIconView.widthAnchor.constraint(equalToConstant: iconSize),
            downIconView.heightAnchor.constraint(equalToConstant: iconSize),

            downLabel.leadingAnchor.constraint(equalTo: downIconView.trailingAnchor, constant: 2),
            downLabel.centerYAnchor.constraint(equalTo: downIconView.centerYAnchor),
            downLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),

            // 分割线
            divider.topAnchor.constraint(equalTo: downIconView.bottomAnchor, constant: 2),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // 第二行：上行
            upIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            upIconView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 2),
            upIconView.widthAnchor.constraint(equalToConstant: iconSize),
            upIconView.heightAnchor.constraint(equalToConstant: iconSize),

            upLabel.leadingAnchor.constraint(equalTo: upIconView.trailingAnchor, constant: 2),
            upLabel.centerYAnchor.constraint(equalTo: upIconView.centerYAnchor),
            upLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            upLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    /// 更新显示速度
    func update(downSpeed: String, upSpeed: String) {
        downLabel.stringValue = "\(downSpeed)/s"
        upLabel.stringValue = "\(upSpeed)/s"
        invalidateIntrinsicContentSize()
    }
}
