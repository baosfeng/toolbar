import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 关于页

/// 关于设置页 — 版本、构建号、项目地址、检查更新、安装与退出
///
/// 版本号来自 `Info.plist`（打包脚本注入），未打包时退回 "—" 而不是显示 0。
///
/// 更新口径（1.30 起）：**能装**，但代价如实写在界面上——本应用 ad-hoc 签名，
/// 替换包体后 cdhash 变化，TCC 授权（屏幕录制 / 辅助功能 / 输入监控）与登录项
/// 需要重新授权。所以「下载并安装」只在用户点了才走，自动安装默认关。
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
    private let notesRow = SettingsAboutNotesRow()
    private let releaseRow = SettingsRowView(title: "发布页")
    private let installCard = SettingsAboutInstallCard()

    private let currentVersionLabel = MenuPanelLabel.text("—", font: SettingsTheme.rowValueFont,
                                                          color: SettingsTheme.textSecondary)
    private let latestVersionLabel = MenuPanelLabel.text("—", font: SettingsTheme.rowValueFont,
                                                         color: SettingsTheme.textSecondary)
    private let statusLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
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
        buildInstallCard()
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
        releaseRow.trailingStack.addArrangedSubview(releaseButton)

        let updateCard = SettingsCardView()
        [currentRow, latestRow, statusRow, notesRow, releaseRow].forEach(updateCard.addRow)
        page.addCard(updateCard, sectionTitle: "检查更新")
        page.addNote("启动后每 24 小时最多自动查询一次；手动点「检查更新」不受限制。" + "新版本说明在固定高度区域里滚动，完整内容见发布页。")

        refreshUpdateSection()
    }

    // MARK: - 安装卡

    private func buildInstallCard() {
        installCard.installButton.target = self
        installCard.installButton.action = #selector(installUpdate)
        installCard.autoSwitch.target = self
        installCard.autoSwitch.action = #selector(toggleAutoInstall)
        page.addCard(installCard.card, sectionTitle: "安装")
        page.addNote("安装会把新版本下载到临时目录、校验版本后替换当前应用包并重启。" + "\(AppIdentity.displayName) 当前使用 ad-hoc 签名：替换后 cdhash 变化，" + "屏幕录制 / 辅助功能 / 输入监控与登录项可能需要重新授权。")
        refreshInstallSection()
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
        updateCheck.onInstallStateChange = { [weak self] in self?.refreshInstallSection() }
        refreshUpdateSection()
        refreshInstallSection()
    }

    /// 状态 → 三行文案 + 说明区 + 两个按钮（派生口径全部在 `NetworkMonitorUI`，这里只赋值）
    private func refreshUpdateSection() {
        let presentation = UpdateCheckText.presentation(for: updateCheck.state,
                                                        lastCheckAt: updateCheck.lastCheckAt)
        currentVersionLabel.stringValue = updateCheck.currentVersionText
        latestVersionLabel.stringValue = presentation.latestVersionText
        latestVersionLabel.textColor = presentation.highlightsLatest ? SettingsTheme.accent
                                                                     : SettingsTheme.textSecondary
        statusLabel.stringValue = presentation.statusText
        checkButton.title = presentation.checkButtonTitle
        checkButton.isEnabled = presentation.canCheck
        checkButton.setAccessibilityLabel(presentation.checkButtonTitle)

        // 说明区：有新版本时按分块渲染原始 body；没有新版本保持占位口径（—）
        let rawNotes = updateCheck.latestNotes
        let hasNotes = !UpdateNotes.blocks(rawNotes).isEmpty
        notesRow.notesView.update(lines: hasNotes ? UpdateNotes.lines(rawNotes) : [],
                                 placeholder: UpdateCheckText.placeholder)
    }

    /// 安装状态 → 安装卡（按钮可用性 = 有新版本 + 支持安装 + 不在执行中）
    private func refreshInstallSection() {
        let hasUpdate: Bool
        if case .available = updateCheck.state { hasUpdate = true } else { hasUpdate = false }
        installCard.update(state: updateCheck.installState,
                           hasUpdate: hasUpdate,
                           canInstall: updateCheck.canInstall,
                           autoInstallEnabled: updateCheck.autoInstallEnabled)
    }

    // MARK: - 动作

    @objc private func checkForUpdates() {
        updateCheck.check()
    }

    @objc private func installUpdate() {
        updateCheck.install()
    }

    @objc private func toggleAutoInstall() {
        updateCheck.setAutoInstallEnabled(installCard.autoSwitch.state == .on)
        refreshInstallSection()
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
    /// 快照 / 探针取证：把「检查更新」区可见文本、说明区行数与四个按钮的无障碍信息打出来
    ///
    /// 离屏快照看不出滚动区里的内容与按钮的可读名，取证以这里打印的真值为准。
    func debugLogUpdateSection(_ tag: String) {
        print("[update-probe][\(tag)] 当前版本=\(currentVersionLabel.stringValue)"
              + " | 最新版本=\(latestVersionLabel.stringValue)"
              + " | 状态=\(statusLabel.stringValue)"
              + " | 说明区 \(notesRow.notesView.debugProbeText)")
        print("[update-probe][\(tag)] 安装卡 \(installCard.debugProbeText)")
        debugLogButton("checkButton", checkButton, tag: tag)
        debugLogButton("releaseButton", releaseButton, tag: tag)
        debugLogButton("installButton", installCard.installButton, tag: tag)
    }

    /// 按钮的读屏真值：role / label / 是否是无障碍元素 / 能否键盘聚焦 / 有没有 press 动作
    private func debugLogButton(_ name: String, _ button: NSButton, tag: String) {
        print("[update-probe][\(tag)] \(name) title=\(button.title)"
              + " role=\(button.accessibilityRole()?.rawValue ?? "nil")"
              + " isElement=\(button.isAccessibilityElement())"
              + " label=\(button.accessibilityLabel() ?? "nil")"
              + " enabled=\(button.isEnabled)"
              + " keyboard=\(button.acceptsFirstResponder)"
              + " press=\(button.responds(to: NSSelectorFromString("accessibilityPerformPress")))")
    }

    /// 取证：从无障碍层按一次「检查更新」，证明按钮默认动作真的走到 action
    func debugPerformAccessibilityPress() {
        checkButton.accessibilityPerformPress()
    }
#endif
}