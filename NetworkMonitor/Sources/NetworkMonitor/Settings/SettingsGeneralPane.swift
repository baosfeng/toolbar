import AppKit
import NetworkMonitorCore

// MARK: - 通用设置页

/// 通用设置 — 启动行为与额度提醒
///
/// 两个开关都写进既有偏好实现（`LaunchAtStartupService` / `BillingAlertPreferences`），
/// 与菜单栏齿轮菜单读同一份状态，避免两处勾选态不一致。
final class SettingsGeneralPane: SettingsPaneView {

    private let launchAtStartup: LaunchAtStartupService
    private let alertPreferences: BillingAlertPreferences
    private let launchRow = SettingsRowView(title: "开机自启动",
                                            subtitle: "登录后自动启动 NetworkMonitor")
    private let alertRow = SettingsRowView(title: "额度阈值提醒",
                                           subtitle: "剩余跌破 5% / 4% / 3% / 2% / 1% 时发送系统通知")
    private let launchSwitch = NSSwitch()
    private let alertSwitch = NSSwitch()

    init(launchAtStartup: LaunchAtStartupService = LaunchAtStartupService(),
         alertPreferences: BillingAlertPreferences = BillingAlertPreferences()) {
        self.launchAtStartup = launchAtStartup
        self.alertPreferences = alertPreferences
        super.init(section: .general)
    }

    override func buildContent() {
        launchSwitch.target = self
        launchSwitch.action = #selector(launchChanged)
        launchSwitch.setAccessibilityLabel("开机自启动")
        alertSwitch.target = self
        alertSwitch.action = #selector(alertChanged)
        alertSwitch.setAccessibilityLabel("额度阈值提醒")

        launchRow.trailingStack.addArrangedSubview(launchSwitch)
        alertRow.trailingStack.addArrangedSubview(alertSwitch)

        let launchCard = SettingsCardView()
        launchCard.addRow(launchRow)

        let alertCard = SettingsCardView()
        alertCard.addRow(alertRow)

        page.addCard(launchCard, sectionTitle: "启动")
        page.addCard(alertCard, sectionTitle: "额度提醒")
        page.addNote("设置会立即生效；开机自启动依赖应用签名，未签名构建可能被系统拒绝。")
    }

    override func refresh() {
        launchSwitch.state = launchAtStartup.isEnabled ? .on : .off
        alertSwitch.state = alertPreferences.isEnabled ? .on : .off
        launchRow.update(subtitle: launchAtStartup.isEnabled
                         ? "登录后自动启动 NetworkMonitor"
                         : "当前未登记开机自启动")
    }

    // MARK: - 动作

    @objc private func launchChanged() {
        let target = launchSwitch.state == .on
        let ok = launchAtStartup.setEnabled(target)
        if !ok {
            // 系统拒绝时回滚界面状态，避免显示已开启但实际没启动
            launchSwitch.state = target ? .off : .on
            launchRow.update(subtitle: "系统未允许开机自启动（需在系统设置中检查登录项）")
        } else {
            launchRow.update(subtitle: target
                             ? "登录后自动启动 NetworkMonitor"
                             : "当前未登记开机自启动")
        }
    }

    @objc private func alertChanged() {
        alertPreferences.setEnabled(alertSwitch.state == .on)
    }
}
