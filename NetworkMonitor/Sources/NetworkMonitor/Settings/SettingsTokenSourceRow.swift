import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 单个来源一行（状态点 + 名称 + 路径 + 开关）

/// 来源清单的一行 —— 复刻额度 Provider 的实例行形态
///
/// 为什么不用 SettingsRowView：状态点要排在名称左边，而 SettingsRowView 的标题栈是私有的，
/// 只能往右侧 trailingStack 塞控件。这里按同一套度量（卡片内边距 / 行高 / 行内边距）自己排一行，
/// 视觉与 SettingsRowView 对齐，行为上只多一个左侧状态点。
final class SettingsTokenSourceRowView: NSView {

    let source: TokenSourceID
    private let dot = SettingsStatusDotView()
    private let nameLabel: NSTextField
    private let subtitleLabel: NSTextField
    let toggle = NSSwitch()
    /// 「选择目录…」只在启用时出现（未启用时改目录没有意义）
    let chooseButton: NSButton

    var onToggle: ((Bool) -> Void)?
    var onChoose: (() -> Void)?

    init(source: TokenSourceID) {
        self.source = source
        nameLabel = MenuPanelLabel.text(source.displayName, font: SettingsTheme.rowTitleFont,
                                        color: SettingsTheme.textPrimary)
        subtitleLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                            color: SettingsTheme.textSecondary)
        // SQLite 源的 rootPath 是 db 文件本身，按钮与无障碍文案都要跟着说「数据库」
        chooseButton = SettingsLinkButton.make(source.isSQLite ? "选择数据库…" : "选择目录…",
                                              target: nil, action: #selector(chooseTapped))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chooseButton.target = self
        chooseButton.setAccessibilityLabel(source.isSQLite
                                           ? "选择 " + source.displayName + " 的数据库文件"
                                           : "选择 " + source.displayName + " 的会话目录")
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("启用 " + source.displayName + " 用量来源")

        let labels = NSStackView(views: [nameLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = SettingsTheme.rowLabelSpacing

        let trailing = NSStackView(views: [chooseButton, toggle])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.spacing = 8
        trailing.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [dot, labels, MenuPanelLabel.spacer(), trailing])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsTheme.cardPaddingX),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsTheme.cardPaddingX),
            row.topAnchor.constraint(equalTo: topAnchor, constant: SettingsTheme.rowPaddingY),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsTheme.rowPaddingY),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsTheme.rowHeight),
        ])
        setAccessibilityLabel(source.displayName + " 来源")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 刷新一行（状态点语义色 / 路径 / 开关态 / 目录链接显隐）
    func update(path: String, status: TokenSourceStatus, counts: String?, enabled: Bool) {
        // 文件型说「目录」、SQLite 型说「数据库文件」：同一套四档判据，措辞按来源类型分流
        let isSQLite = source.isSQLite
        let subtitle = TokenSourceStatusText.subtitle(path: path, status: status, counts: counts,
                                                      isSQLite: isSQLite)
        subtitleLabel.stringValue = subtitle
        // 副标题单行会截断：tooltip 给完整文案，路径与状态都能看全
        subtitleLabel.toolTip = subtitle
        dot.setColor(color(for: status))
        toggle.state = enabled ? .on : .off
        chooseButton.isHidden = !enabled
        let note = TokenSourceStatusText.note(for: status, isSQLite: isSQLite)
        toggle.toolTip = note
        var reading = source.displayName + "，" + (enabled ? "已启用" : "未启用") + "，"
        reading += path.isEmpty ? (isSQLite ? "未配置数据库文件" : "未配置目录") : path
        if let counts { reading += "，" + counts }
        if let note { reading += "，" + note }
        setAccessibilityLabel(reading)
    }

    /// 开关不可用（未安装时不给点亮，避免「开了却什么都没扫到」）
    func setToggleEnabled(_ canEnable: Bool) {
        toggle.isEnabled = canEnable
    }

    private func color(for status: TokenSourceStatus) -> NSColor {
        switch status {
        case .ok: return SettingsTheme.okInk
        case .unreadable: return SettingsTheme.destructive
        case .noSessions, .noTelemetry: return SettingsTheme.warnInk
        case .notInstalled: return SettingsTheme.ghost
        }
    }

    @objc private func toggleChanged() { onToggle?(toggle.state == .on) }
    @objc private func chooseTapped() { onChoose?() }
}
