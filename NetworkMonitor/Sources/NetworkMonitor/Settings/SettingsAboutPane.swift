import AppKit

// MARK: - 关于页

/// 关于设置页 — 版本、构建号、项目地址与退出
///
/// 版本号来自 `Info.plist`（打包脚本注入），未打包时退回 "—" 而不是显示 0。
final class SettingsAboutPane: SettingsPaneView {

    private let versionRow = SettingsRowView(title: "版本")
    private let buildRow = SettingsRowView(title: "构建号")
    private let repoRow = SettingsRowView(title: "项目地址",
                                          subtitle: "github.com/baosfeng/toolbar")
    private let quitRow = SettingsRowView(title: "退出 NetworkMonitor")

    init() {
        super.init(section: .about)
    }

    override func buildContent() {
        versionRow.trailingStack.addArrangedSubview(valueLabel(Self.shortVersion))
        buildRow.trailingStack.addArrangedSubview(valueLabel(Self.buildVersion))

        let openButton = NSButton(title: "打开", target: self, action: #selector(openRepository))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.setAccessibilityLabel("打开项目地址")
        repoRow.trailingStack.addArrangedSubview(openButton)

        let quitButton = NSButton(title: "退出", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.contentTintColor = .systemRed
        quitButton.setAccessibilityLabel("退出 NetworkMonitor")
        quitRow.trailingStack.addArrangedSubview(quitButton)

        let appCard = SettingsCardView()
        appCard.addRow(versionRow)
        appCard.addRow(buildRow)
        appCard.addRow(repoRow)
        page.addCard(appCard, sectionTitle: "应用")

        let quitCard = SettingsCardView()
        quitCard.addRow(quitRow)
        page.addCard(quitCard, sectionTitle: "会话")
        page.addNote("NetworkMonitor 是菜单栏应用：关闭本窗口不会退出，退出请用上面的按钮或齿轮菜单。")
    }

    // MARK: - 动作

    @objc private func openRepository() {
        guard let url = URL(string: "https://github.com/baosfeng/toolbar") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 版本

    /// 只读值标签（等宽数字，右对齐）
    private func valueLabel(_ text: String) -> NSTextField {
        let label = MenuPanelLabel.text(text, font: SettingsStyle.rowValueFont,
                                        color: .secondaryLabelColor)
        label.alignment = .right
        return label
    }

    private static var shortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    private static var buildVersion: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }
}
