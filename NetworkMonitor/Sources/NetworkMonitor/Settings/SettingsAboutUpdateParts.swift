import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 说明行（标题 + 滚动说明区）

/// 「新版本说明」行 —— 左侧标题，下方一整块固定高度的说明区
///
/// 为什么不是 `SettingsRowView`：行是「左标题 + 右控件」的单行结构，
/// 而说明区要占满整行宽度并在内部滚动，塞进 trailingStack 只会被压成一条窄柱。
final class SettingsAboutNotesRow: NSView {

    private let titleLabel = MenuPanelLabel.text("新版本说明", font: SettingsTheme.rowTitleFont,
                                                 color: SettingsTheme.textPrimary)
    let notesView = SettingsReleaseNotesView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, notesView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor,
                                           constant: SettingsTheme.cardPaddingX),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor,
                                            constant: -SettingsTheme.cardPaddingX),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: SettingsTheme.rowPaddingY),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsTheme.rowPaddingY),
            notesView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

// MARK: - 安装卡

/// 安装卡 —— 「下载并安装」按钮 + 自动安装开关 + 进度/失败文案
///
/// 破坏性动作的代价写在界面上而不是藏起来：替换应用包会让 ad-hoc 签名的 TCC 授权失效，
/// 所以这一卡永远带着「重启后可能需要重新授权」的说明，且自动安装默认关。
final class SettingsAboutInstallCard: NSView {

    private let statusRow = SettingsRowView(title: "安装")
    private let autoRow = SettingsRowView(title: "自动下载安装",
                                          subtitle: "发现新版本后自动下载、校验、替换并重启（默认关闭）")
    let installButton = NSButton()
    let autoSwitch = NSSwitch()
    private let statusLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                  color: SettingsTheme.textSecondary)
    private let footnoteLabel = MenuPanelLabel.text("", font: SettingsTheme.noteFont,
                                                    color: SettingsTheme.textTertiary)

    /// 标题行 / 安装行 / 说明行挂在这张卡上（外层容器只为把它与页面宽度对齐）
    let card = SettingsCardView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        statusRow.trailingStack.addArrangedSubview(statusLabel)
        statusRow.trailingStack.addArrangedSubview(installButton)
        autoRow.trailingStack.addArrangedSubview(autoSwitch)

        installButton.bezelStyle = .rounded
        installButton.controlSize = .small
        SettingsControlChrome.applyStandardHeight(to: installButton)
        installButton.setAccessibilityLabel("下载并安装")
        installButton.setAccessibilityHelp("下载本机架构的安装包，校验版本后替换当前应用并重启")

        autoSwitch.setAccessibilityLabel("自动下载安装")
        autoSwitch.setAccessibilityHelp("关闭时只在关于页提示新版本；开启后自动替换应用包并重启")

        statusLabel.alignment = .right

        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        footnoteLabel.maximumNumberOfLines = 0
        footnoteLabel.lineBreakMode = .byWordWrapping
        footnoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let noteContainer = NSView()
        noteContainer.translatesAutoresizingMaskIntoConstraints = false
        noteContainer.addSubview(footnoteLabel)
        NSLayoutConstraint.activate([
            footnoteLabel.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor,
                                                   constant: SettingsTheme.cardPaddingX),
            footnoteLabel.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor,
                                                    constant: -SettingsTheme.cardPaddingX),
            footnoteLabel.topAnchor.constraint(equalTo: noteContainer.topAnchor, constant: 4),
            footnoteLabel.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor, constant: -6),
        ])

        card.addRow(statusRow)
        card.addRow(autoRow)
        card.addRow(noteContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 按安装状态刷新（文案口径全部在 `UpdateInstallText`）
    ///
    /// - Parameter hasUpdate: 是否发现新版本（没有新版本时按钮置灰但仍可见，避免按钮忽隐忽现）
    func update(state: UpdateInstallState, hasUpdate: Bool, canInstall: Bool, autoInstallEnabled: Bool) {
        let line = UpdateInstallText.statusLine(state)
        statusLabel.stringValue = line ?? (hasUpdate ? "有新版本可安装" : "没有可安装的新版本")
        statusLabel.textColor = state.stage == .failed ? SettingsTheme.warnInk : SettingsTheme.textSecondary
        installButton.title = UpdateInstallText.buttonTitle(state)
        installButton.isEnabled = canInstall && hasUpdate && UpdateInstallText.canInstall(state)
        installButton.setAccessibilityLabel(UpdateInstallText.buttonTitle(state))
        autoSwitch.state = autoInstallEnabled ? .on : .off
        footnoteLabel.stringValue = UpdateInstallText.footnote(state, autoInstallEnabled: autoInstallEnabled)
        footnoteLabel.textColor = (state.stage == .readyToRelaunch || state.stage == .failed)
            ? SettingsTheme.warnInk : SettingsTheme.textTertiary
    }

    #if DEBUG
    /// 取证：安装卡可见真值（离屏快照读不到按钮态与提示文案）
    var debugProbeText: String {
        let parts = ["status=\(statusLabel.stringValue)",
                     "button=\(installButton.title)",
                     "enabled=\(installButton.isEnabled)",
                     "auto=\(autoSwitch.state == .on)",
                     "note=\(footnoteLabel.stringValue)"]
        return parts.joined(separator: " ")
    }
    #endif
}