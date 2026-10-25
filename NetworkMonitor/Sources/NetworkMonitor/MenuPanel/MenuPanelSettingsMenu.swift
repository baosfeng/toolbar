import AppKit

// MARK: - 标题栏设置菜单

/// 标题栏齿轮的菜单构建与响应
///
/// 拆出原因：`MenuPanelView` 主体接近单文件 15 KiB 上限；菜单项与勾选态逻辑独立成扩展。
/// 用 `NSPopUpButton`（pullsDown）而非手动 `NSMenu.popUp`：popover 内手动弹菜单会让
/// `.transient` 行为的面板先失焦收起，点开菜单的同时面板就消失了。
extension MenuPanelView: NSMenuDelegate {

    /// 「开机自启动」菜单项标识（`menuNeedsUpdate` 据此刷新勾选态）
    private static var launchMenuItemTag: Int { 0x1D0 }

    /// 配置齿轮按钮与菜单项（init 时调用一次）
    func configureSettingsButton() {
        settingsButton.isBordered = false
        settingsButton.bezelStyle = .inline
        settingsButton.autoenablesItems = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.toolTip = "设置"
        settingsButton.setAccessibilityLabel("设置")

        // 第 0 项是 pullsDown 模式的标题位，只承载齿轮图标
        settingsButton.addItem(withTitle: "")
        settingsButton.item(at: 0)?.image = NSImage(systemSymbolName: "gearshape",
                                                    accessibilityDescription: "设置")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))

        addSettingsMenuItem(title: "设置…",
                            action: #selector(handleOpenSettings),
                            keyEquivalent: ",")
        settingsButton.menu?.addItem(.separator())
        addSettingsMenuItem(title: "开机自启动",
                            action: #selector(handleToggleLaunchAtStartup),
                            tag: Self.launchMenuItemTag)
        settingsButton.menu?.addItem(.separator())
        addSettingsMenuItem(title: "退出 NetworkMonitor",
                            action: #selector(handleQuit),
                            keyEquivalent: "q")

        settingsButton.menu?.autoenablesItems = false
        settingsButton.menu?.delegate = self

        NSLayoutConstraint.activate([
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    /// 追加一个菜单项（target 固定为本视图）
    private func addSettingsMenuItem(title: String, action: Selector,
                                     keyEquivalent: String = "", tag: Int = 0) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.tag = tag
        settingsButton.menu?.addItem(item)
    }

    /// 菜单弹出前刷新勾选态（开机自启动的真实状态由控制器同步）
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: Self.launchMenuItemTag)?.state = launchAtStartupEnabled ? .on : .off
    }

    // MARK: - 菜单动作

    @objc private func handleOpenSettings() {
        delegate?.menuPanelViewDidRequestSettings(self, section: nil)
    }

    @objc private func handleToggleLaunchAtStartup() {
        delegate?.menuPanelViewDidRequestToggleLaunchAtStartup(self)
    }

    @objc private func handleQuit() {
        delegate?.menuPanelViewDidRequestQuit(self)
    }
}