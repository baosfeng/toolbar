import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 签名变化提示带

/// 「本次更新后签名已变化」提示带 —— 只在检测到签名身份变化时出现，首启动与正常升级都隐藏
///
/// 形状：bandFill 底的圆角块，左侧告警灯 + 三行说明（标题 / 正文 / 待重授清单），
/// 右下角「打开系统设置」走权限中心的既有深链（本视图不拼任何 URL）。
/// 判据与文案全部来自 `SigningIdentityNotice`，这里只负责摆控件。
@MainActor
final class SettingsSigningNoticeBand: NSView {

    private let dot = SettingsStatusDotView()
    private let titleLabel = MenuPanelLabel.text("", font: SettingsTheme.rowTitleFont,
                                                 color: SettingsTheme.textPrimary)
    private let detailLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                                  color: SettingsTheme.textSecondary)
    private let pendingLabel = MenuPanelLabel.text("", font: SettingsTheme.noteFont,
                                                   color: SettingsTheme.warnInk)
    /// 「打开系统设置」文字链（target / action 在 init 里接：属性初始化阶段拿不到 self）
    private let actionButton = SettingsLinkButton.make("打开系统设置", target: nil,
                                                       action: #selector(NSResponder.doCommand(by:)))

    /// 「打开系统设置」的落点（由页面注入权限协议，视图不拼深链）
    var onOpenSettings: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isHidden = true
        dot.setColor(SettingsTheme.warnInk)

        titleLabel.maximumNumberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping
        pendingLabel.maximumNumberOfLines = 0
        pendingLabel.lineBreakMode = .byWordWrapping

        actionButton.target = self
        actionButton.action = #selector(openSettings)
        actionButton.setAccessibilityLabel("打开系统设置")
        actionButton.setAccessibilityLabel("打开系统设置")
        actionButton.setAccessibilityHelp("跳到系统设置里逐项重新允许被系统拒绝的权限")

        let textStack = NSStackView(views: [titleLabel, detailLabel, pendingLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = SettingsTheme.noteGap
        textStack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, detailLabel, pendingLabel].forEach {
            $0.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        }

        let headRow = NSStackView(views: [dot, textStack])
        headRow.orientation = .horizontal
        headRow.alignment = .top
        headRow.spacing = SettingsTheme.statusDotSpacing
        headRow.translatesAutoresizingMaskIntoConstraints = false

        let footRow = NSStackView(views: [MenuPanelLabel.spacer(), actionButton])
        footRow.orientation = .horizontal
        footRow.alignment = .centerY
        footRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [headRow, footRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsTheme.noteGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsTheme.cardPaddingX),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsTheme.cardPaddingX),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: SettingsTheme.cardPaddingY + 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsTheme.cardPaddingY - 2),
            headRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 按提示口径刷新（nil 或不可见 = 整块隐藏，不占位）
    func update(_ notice: SigningIdentityNotice?, snapshot: SystemPermissionSnapshot) {
        guard let notice, notice.isVisible else {
            isHidden = true
            return
        }
        isHidden = false
        titleLabel.stringValue = notice.headline
        detailLabel.stringValue = notice.detail
        let pending = notice.pendingLine(in: snapshot)
        pendingLabel.stringValue = pending
        pendingLabel.isHidden = pending.isEmpty
        setAccessibilityLabel([notice.headline, notice.detail, pending]
            .filter { !$0.isEmpty }.joined(separator: "，"))
        needsLayout = true
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = SettingsTheme.bandFill.cgColor
        layer?.cornerRadius = SettingsTheme.statusBandRadius
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
