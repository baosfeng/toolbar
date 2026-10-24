import AppKit

// MARK: - 标签工厂（拆出自 MenuPanelComponents.swift，原文件超单文件 15 KiB 上限）

/// 面板标签构造 — 统一字体/颜色/截断方式，避免各处手写 NSTextField 参数
@MainActor
enum MenuPanelLabel {

    /// 普通标签
    static func text(_ content: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: content)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    /// 分区标题（次要色 + 小号加粗）
    static func section(_ content: String) -> NSTextField {
        text(content, font: MenuPanelStyle.sectionFont, color: MenuPanelStyle.secondaryText)
    }

    /// 弹性占位视图（NSStackView 中撑开两侧内容）
    static func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return spacer
    }

    /// 数值标签（等宽数字）
    static func value(_ content: String, color: NSColor = .labelColor) -> NSTextField {
        text(content, font: MenuPanelStyle.valueFont, color: color)
    }

    /// SF Symbol 图标视图（模板色随语义色，禁止 emoji）
    static func symbol(_ name: String, pointSize: CGFloat = 12, color: NSColor = .secondaryLabelColor) -> NSImageView? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let imageView = NSImageView()
        imageView.image = image.withSymbolConfiguration(config) ?? image
        imageView.contentTintColor = color
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: pointSize + 4),
            imageView.heightAnchor.constraint(equalToConstant: pointSize + 4),
        ])
        return imageView
    }
}
