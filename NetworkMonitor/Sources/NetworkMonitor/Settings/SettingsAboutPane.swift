import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 关于页

/// 关于设置页 — 版本、构建号、项目地址、检查更新与退出
///
/// 版本号来自 `Info.plist`（打包脚本注入），未打包时退回 "—" 而不是显示 0。
///
/// 「检查更新」只提示 + 打开浏览器，**不自动下载、不自动替换 .app**：
/// 本应用自签名 / ad-hoc 签名，替换包体后 TCC 授权（屏幕录制 / 辅助功能）全部失效，
/// 自动安装反而是让用户丢权限。安装由用户点发布页自己完成。
final class SettingsAboutPane: SettingsPaneView {

    private let updateCheck: UpdateCheckService

    // MARK: 应用卡

    private let versionRow = SettingsRowView(title: "版本")
    private let buildRow = SettingsRowView(title: "构建号")
    private let repoRow = SettingsRowView(title: "项目地址",
                                          subtitle: "github.com/baosfeng/toolbar")
    private let quitRow = SettingsRowView(title: "退出 \(AppIdentity.displayName)")

    // MARK: 检查更新区

    private let currentRow = SettingsRowView(title: "当前版本")
    private let latestRow = SettingsRowView(title: "最新版本")
    private let statusRow = SettingsRowView(title: "状态")
    private let notesRow = SettingsRowView(title: "新版本说明")
    private let releaseRow = SettingsRowView(title: "发布页")

    private let currentVersionLabel = MenuPanelLabel.text("—", font: SettingsTheme.rowValueFont,
                                                          color: SettingsTheme.textSecondary)
    private let latestVersionLabel = MenuPanelLabel.text("—", font: SettingsTheme.rowValueFont,
                                                         color: SettingsTheme.textSecondary)
    private let statusLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                  color: SettingsTheme.textSecondary)
    private let notesLabel = MenuPanelLabel.text("—", font: SettingsTheme.rowSubtitleFont,
                                                 color: SettingsTheme.textSecondary)
    private let checkButton = NSButton()
    private let releaseButton = NSButton()

    init(updateCheck: UpdateCheckService) {
        self.updateCheck = updateCheck
        super.init(section: .about)
    }

    override func buildContent() {
        buildApplicationCard()
        buildUpdateCard()
        buildSessionCard()
    }

    // MARK: - 应用卡

    private func buildApplicationCard() {
        versionRow.trailingStack.addArrangedSubview(valueLabel(Self.shortVersion))
        buildRow.trailingStack.addArrangedSubview(valueLabel(Self.buildVersion))

        let openButton = NSButton(title: "打开", target: self, action: #selector(openRepository))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.setAccessibilityLabel("打开项目地址")
        SettingsControlChrome.applyStandardHeight(to: openButton)
        repoRow.trailingStack.addArrangedSubview(openButton)

        let appCard = SettingsCardView()
        appCard.addRow(versionRow)
        appCard.addRow(buildRow)
        appCard.addRow(repoRow)
        page.addCard(appCard, sectionTitle: "应用")
    }

    // MARK: - 检查更新卡

    private func buildUpdateCard() {
        configureValueLabel(currentVersionLabel)
        configureValueLabel(latestVersionLabel)
        configureValueLabel(statusLabel)

        // 说明是正文而不是行值：左对齐、单行尾部省略、完整摘要挂 toolTip（悬停可见 + 读屏念全文）
        // 单行是版式取舍：关于页已超一屏，说明涨成三行会把「会话」卡推到需要多滚一屏
        notesLabel.alignment = .left
        notesLabel.maximumNumberOfLines = 1
        notesLabel.lineBreakMode = .byTruncatingTail
        notesLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        notesLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        notesLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true

        configureActionButton(checkButton, title: "检查更新", action: #selector(checkForUpdates))
        checkButton.setAccessibilityHelp("向 GitHub 查询最新发布版本，只读、匿名、不带用户标识")
        configureActionButton(releaseButton, title: "打开发布页", action: #selector(openReleasePage))
        releaseButton.setAccessibilityHelp("在浏览器中打开 GitHub 发布页，手动下载新版本")
        // 显式声明角色：自绘 / 动态构建的行里，按钮的默认角色要等无障碍树首次查询才成型，
        // 显式给 .button 后读屏与探针都能立刻拿到 AXButton
        checkButton.setAccessibilityElement(true)
        checkButton.setAccessibilityRole(.button)
        releaseButton.setAccessibilityElement(true)
        releaseButton.setAccessibilityRole(.button)

        currentRow.trailingStack.addArrangedSubview(currentVersionLabel)
        latestRow.trailingStack.addArrangedSubview(latestVersionLabel)
        statusRow.trailingStack.addArrangedSubview(statusLabel)
        statusRow.trailingStack.addArrangedSubview(checkButton)
        notesRow.trailingStack.addArrangedSubview(notesLabel)
        releaseRow.trailingStack.addArrangedSubview(releaseButton)

        let updateCard = SettingsCardView()
        [currentRow, latestRow, statusRow, notesRow, releaseRow].forEach(updateCard.addRow)
        page.addCard(updateCard, sectionTitle: "检查更新")
        page.addNote("启动后每 24 小时最多自动查询一次；手动点「检查更新」不受限制。"
                     + "只提示新版本，不自动下载、不替换应用包（自签名应用替换包体会让屏幕录制 / 辅助功能授权失效）。")

        refreshUpdateSection()
    }

    // MARK: - 会话卡

    private func buildSessionCard() {
        let quitButton = NSButton(title: "退出", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.contentTintColor = SettingsTheme.destructive
        quitButton.setAccessibilityLabel("退出 \(AppIdentity.displayName)")
        SettingsControlChrome.applyStandardHeight(to: quitButton)
        quitRow.trailingStack.addArrangedSubview(quitButton)

        let quitCard = SettingsCardView()
        quitCard.addRow(quitRow)
        page.addCard(quitCard, sectionTitle: "会话")
        page.addNote("\(AppIdentity.displayName) 是菜单栏应用：关闭本窗口不会退出，退出请用上面的按钮或齿轮菜单。")
    }

    // MARK: - 刷新

    /// 切到本页 / 设置窗口重新显示时同步：登记状态回调并立刻灌一次当前值
    ///
    /// 页面每次切页都会重建，回调换成新实例的 weak self；
    /// 旧实例释放后回调自然失效，不需要显式注销。
    override func refresh() {
        updateCheck.onStateChange = { [weak self] in self?.refreshUpdateSection() }
        refreshUpdateSection()
    }

    /// 状态 → 四行文案 + 两个按钮（派生口径全部在 `NetworkMonitorUI`，这里只赋值）
    private func refreshUpdateSection() {
        let presentation = UpdateCheckText.presentation(for: updateCheck.state,
                                                        lastCheckAt: updateCheck.lastCheckAt)
        currentVersionLabel.stringValue = updateCheck.currentVersionText
        latestVersionLabel.stringValue = presentation.latestVersionText
        latestVersionLabel.textColor = presentation.highlightsLatest ? SettingsTheme.accent
                                                                     : SettingsTheme.textSecondary
        statusLabel.stringValue = presentation.statusText
        notesLabel.stringValue = presentation.notesText
        notesLabel.toolTip = presentation.notesText == UpdateCheckText.placeholder
            ? "有新版本时显示发布说明摘要" : presentation.notesText
        checkButton.title = presentation.checkButtonTitle
        checkButton.isEnabled = presentation.canCheck
        checkButton.setAccessibilityLabel(presentation.checkButtonTitle)
    }

    // MARK: - 动作

    @objc private func checkForUpdates() {
        updateCheck.check()
    }

    @objc private func openReleasePage() {
        let fallback = URL(string: "https://github.com/baosfeng/toolbar/releases")!
        NSWorkspace.shared.open(updateCheck.releasePageURL ?? fallback)
    }

    @objc private func openRepository() {
        guard let url = URL(string: "https://github.com/baosfeng/toolbar") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 控件

    /// 只读值标签（等宽数字，右对齐）
    private func valueLabel(_ text: String) -> NSTextField {
        let label = MenuPanelLabel.text(text, font: SettingsTheme.rowValueFont,
                                        color: SettingsTheme.textSecondary)
        label.alignment = .right
        return label
    }

    /// 行值样式的可复用标签（内容随状态变，不再每次重建）
    private func configureValueLabel(_ label: NSTextField) {
        label.font = SettingsTheme.rowValueFont
        label.textColor = SettingsTheme.textSecondary
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    /// 22pt 标准高按钮（与「打开 / 退出」同一档，保证整页横线对齐）
    private func configureActionButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
        SettingsControlChrome.applyStandardHeight(to: button)
    }

    // MARK: - 版本

    private static var shortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    private static var buildVersion: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    // MARK: - 取证

#if DEBUG
    /// 快照 / 探针取证：把「检查更新」区四行可见文本与两个按钮的无障碍信息打出来
    ///
    /// 离屏快照看不出按钮的可读名与可键盘态，取证以这里打印的真值为准。
    func debugLogUpdateSection(_ tag: String) {
        print("[update-probe][\(tag)] 当前版本=\(currentVersionLabel.stringValue)"
              + " | 最新版本=\(latestVersionLabel.stringValue)"
              + " | 状态=\(statusLabel.stringValue)"
              + " | 说明=\(notesLabel.stringValue)")
        debugLogButton("checkButton", checkButton, tag: tag)
        debugLogButton("releaseButton", releaseButton, tag: tag)
    }

    /// 按钮的读屏真值：role / label / 是否是无障碍元素 / 能否键盘聚焦 / 有没有 press 动作
    private func debugLogButton(_ name: String, _ button: NSButton, tag: String) {
        print("[update-probe][\(tag)] \(name) title=\(button.title)"
              + " role=\(button.accessibilityRole()?.rawValue ?? "nil")"
              + " isElement=\(button.isAccessibilityElement())"
              + " label=\(button.accessibilityLabel() ?? "nil")"
              + " keyboard=\(button.acceptsFirstResponder)"
              + " press=\(button.responds(to: NSSelectorFromString("accessibilityPerformPress")))")
    }

    /// 取证：从无障碍层按一次「检查更新」，证明按钮默认动作真的走到 action
    func debugPerformAccessibilityPress() {
        checkButton.accessibilityPerformPress()
    }
#endif
}
