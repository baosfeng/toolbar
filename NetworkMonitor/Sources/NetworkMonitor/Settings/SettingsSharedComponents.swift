import AppKit

// MARK: - 设置页共用控件

/// 拆出原因：`SettingsStatusDotView` 与 `SettingsLinkButton` 被剪贴板 / 截图与贴图 /
/// 局域网互传三页共用；集中一处避免三份复制，也避免主页面文件超过单文件 15 KiB 上限。
/// 后续若要合并进 `SettingsComponents.swift`，可整段平移。

// MARK: 状态点

/// 语义状态点 — 绿=正常/已授权、橙=待授权/异常、灰=停用/未配置
///
/// 只接收语义色（`systemGreen` / `systemOrange` / `tertiaryLabelColor`），不写死 hex；
/// 外观切换时重新解析 `cgColor`，避免深色模式下残留浅色圆点。
final class SettingsStatusDotView: NSView {

    private let dotLayer = CALayer()
    private var semanticColor: NSColor = .tertiaryLabelColor

    init(diameter: CGFloat = 7) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(dotLayer)
        dotLayer.cornerRadius = diameter / 2
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        dotLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    /// 设置状态颜色（传语义色，不传 hex）
    func setColor(_ color: NSColor) {
        semanticColor = color
        updateColor()
    }

    private func updateColor() {
        dotLayer.backgroundColor = semanticColor.cgColor
    }
}

// MARK: 链接按钮

/// 设置页文字链按钮 — 原型 link-btn：无边框、12pt、可指定语义色
@MainActor
enum SettingsLinkButton {

    static func make(_ title: String,
                     target: AnyObject?,
                     action: Selector,
                     color: NSColor = .controlAccentColor) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        setTitle(title, on: button, color: color)
        return button
    }

    /// 更新标题（忽略应用计数等在展开/收起时变化）
    static func setTitle(_ title: String,
                         on button: NSButton,
                         color: NSColor = .secondaryLabelColor) {
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: color,
        ])
        button.setAccessibilityLabel(title)
    }
}
