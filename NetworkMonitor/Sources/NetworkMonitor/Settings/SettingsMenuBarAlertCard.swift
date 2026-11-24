import AppKit
import NetworkMonitorCore

// MARK: - 菜单栏超限告警设置卡

/// 菜单栏超限告警卡 —— 一行开关 + 两个阈值：CPU / 内存超过阈值时给菜单栏标题加 ⚠️
///
/// 为什么单独成卡（而不是塞进「菜单栏显示方式」）：三个偏好键
/// （menuBar.alertsEnabled / cpuAlert / memoryAlert）早就存在、消费端也写好了
/// （MenuBarManager.update），但**从来没有任何控件写过它们** —— 永远是 false，
/// 功能实际是死的。补 UI 时按项目的卡片范式（同 SettingsSmoothScrollCard）自包含成一张卡：
/// 构建 / 回灌 / 动作 / 置灰全在文件内，调用方只需要 addCard + refresh。
///
/// 阈值档位 50%…95%（步进 5%）：偏好存 0…1，两边在这里换算，视图层只认百分比。
@MainActor
final class SettingsMenuBarAlertCard {

    /// 卡片本体 —— 调用方 `page.addCard(card.card, sectionTitle: "菜单栏告警")`
    let card = SettingsCardView()

    private let preferences: MenuBarDisplayPreferences
    /// 写偏好之后的回调（调用方在这里发 AppEvents.postMenuBarDisplayChanged）
    private let onChange: () -> Void

    // MARK: - 控件

    private let masterRow = SettingsRowView(title: "超限告警",
                                            subtitle: "CPU / 内存超过阈值时在菜单栏标题前加 ⚠️")
    private let masterSwitch = NSSwitch()
    private let cpuRow = SettingsRowView(title: "CPU 阈值")
    private let cpuControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let memoryRow = SettingsRowView(title: "内存阈值")
    private let memoryControl = NSPopUpButton(frame: .zero, pullsDown: false)

    /// 可选阈值（百分比，步进 5%）
    static let thresholdPercents: [Int] = Array(stride(from: 50, through: 95, by: 5))

    // MARK: - 初始化

    init(preferences: MenuBarDisplayPreferences,
         onChange: @escaping () -> Void) {
        self.preferences = preferences
        self.onChange = onChange
        buildRows()
        refresh()
    }

    // MARK: - 构建

    private func buildRows() {
        masterSwitch.target = self
        masterSwitch.action = #selector(masterChanged)
        masterSwitch.setAccessibilityLabel("超限告警")
        masterRow.trailingStack.addArrangedSubview(masterSwitch)

        configure(cpuControl, accessibility: "CPU 阈值", action: #selector(cpuChanged))
        cpuRow.trailingStack.addArrangedSubview(cpuControl)
        configure(memoryControl, accessibility: "内存阈值", action: #selector(memoryChanged))
        memoryRow.trailingStack.addArrangedSubview(memoryControl)

        card.addRow(masterRow)
        card.addRow(cpuRow)
        card.addRow(memoryRow)
    }

    private func configure(_ control: NSPopUpButton, accessibility: String, action: Selector) {
        control.addItems(withTitles: Self.thresholdPercents.map { "\($0)%" })
        control.target = self
        control.action = action
        control.setAccessibilityLabel(accessibility)
        control.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: control)
    }

    // MARK: - 刷新

    /// 按偏好灌控件；主开关关着时两个阈值置灰（不隐藏：用户看得见自己的档位还在）
    func refresh() {
        let enabled = preferences.alertsEnabled
        masterSwitch.state = enabled ? .on : .off
        select(cpuControl, percent: Self.percent(of: preferences.cpuAlertThreshold))
        select(memoryControl, percent: Self.percent(of: preferences.memoryAlertThreshold))
        cpuControl.isEnabled = enabled
        memoryControl.isEnabled = enabled
        let hint = enabled ? nil : "先打开上面的「超限告警」"
        cpuRow.update(subtitle: hint)
        memoryRow.update(subtitle: hint)
    }

    private func select(_ control: NSPopUpButton, percent: Int) {
        guard let index = Self.thresholdPercents.firstIndex(of: percent) else { return }
        control.selectItem(at: index)
    }

    // MARK: - 换算

    /// 0…1 的阈值换成下拉里最接近的整数百分比（偏好可能来自手改的值，不硬对齐）
    static func percent(of fraction: Double) -> Int {
        let clamped = min(max(fraction, 0.5), 0.95)
        let raw = Int((clamped * 100).rounded())
        return thresholdPercents.min { abs($0 - raw) < abs($1 - raw) } ?? raw
    }

    /// 下拉选中的百分比换成偏好用的 0…1
    static func fraction(at index: Int) -> Double? {
        guard thresholdPercents.indices.contains(index) else { return nil }
        return Double(thresholdPercents[index]) / 100
    }

    // MARK: - 动作

    @objc private func masterChanged() {
        preferences.alertsEnabled = masterSwitch.state == .on
        refresh()
        onChange()
    }

    @objc private func cpuChanged() {
        guard let value = Self.fraction(at: cpuControl.indexOfSelectedItem) else { return }
        preferences.cpuAlertThreshold = value
        onChange()
    }

    @objc private func memoryChanged() {
        guard let value = Self.fraction(at: memoryControl.indexOfSelectedItem) else { return }
        preferences.memoryAlertThreshold = value
        onChange()
    }
}
