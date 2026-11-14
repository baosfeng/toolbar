import AppKit
import NetworkMonitorCore

// MARK: - 通用设置页

/// 通用设置 —— 启动行为、额度提醒、数值单位，以及可自定义排序的
/// 「菜单栏指标 / 面板分页 / 菜单栏显示方式」三块（排序构建与刷新拆在 +Ordering.swift）
///
/// 开关类写进既有偏好实现（`LaunchAtStartupService` / `BillingAlertPreferences`），
/// 与菜单栏齿轮菜单读同一份状态，避免两处勾选态不一致。
/// 「数值单位」写 `NumberUnitPreferences`（Core），切档后发 `AppEvents.numberUnitStyleChanged`，
/// 菜单面板据此立即重渲染，不用重启。
final class SettingsGeneralPane: SettingsPaneView {

    private let launchAtStartup: LaunchAtStartupService
    private let alertPreferences: BillingAlertPreferences
    private let unitPreferences: NumberUnitPreferences
    private let launchRow = SettingsRowView(title: "开机自启动",
                                            subtitle: "登录后自动启动 NetworkMonitor")
    private let alertRow = SettingsRowView(title: "额度阈值提醒",
                                           subtitle: "剩余跌破 5% / 4% / 3% / 2% / 1% 时发送系统通知")
    private let unitRow = SettingsRowView(title: "数值单位",
                                          subtitle: "Token 与额度数字的量级写法，切换后立即生效")
    private let launchSwitch = NSSwitch()
    private let alertSwitch = NSSwitch()
    private let unitControl = NSPopUpButton(frame: .zero, pullsDown: false)

    // MARK: 排序相关（放宽为 internal：构建与刷新在 SettingsGeneralPane+Ordering.swift）

    /// 键值存储（菜单栏显示偏好与面板分页偏好共用同一份，禁止各页自己 new）
    let storage: any KeyValueStorage
    let displayPreferences: MenuBarDisplayPreferences
    let panelTabPreferences: PanelTabPreferences
    /// 菜单栏指标开关 → 指标（不用 tag 反查：tag 只能存 Int，hashValue 跨启动不稳定）
    var metricByToggle: [NSSwitch: MenuBarMetric] = [:]
    /// 面板分页开关 → 分页
    var tabByToggle: [NSSwitch: MenuPanelTab] = [:]
    var templateControl: NSSegmentedControl?
    var densityControl = NSPopUpButton(frame: .zero, pullsDown: false)
    var unitControl2 = NSPopUpButton(frame: .zero, pullsDown: false)
    var layoutControl = NSPopUpButton(frame: .zero, pullsDown: false)
    var intervalControl = NSPopUpButton(frame: .zero, pullsDown: false)
    /// 菜单栏「单位」行（副标题随档位变化，refresh 时要更新）
    let unit2Row = SettingsRowView(title: "单位")
    /// 可排序卡片的装配器（恢复默认按钮挂在卡片标题行右侧）
    var metricsOrderCard: SettingsOrderedCardView?
    var panelTabsOrderCard: SettingsOrderedCardView?

    /// 快捷模板内部名（`MenuBarDisplayPreferences.applyTemplate` 认这份名字）
    static let templateNames = ["minimal", "performance", "token", "network", "full"]
    /// 快捷模板分段标题（与内部名一一对应）
    static let templateTitles = ["默认", "性能", "Token", "网络", "全部"]

    init(launchAtStartup: LaunchAtStartupService = LaunchAtStartupService(),
         alertPreferences: BillingAlertPreferences = BillingAlertPreferences(),
         unitPreferences: NumberUnitPreferences = NumberUnitPreferences(),
         storage: any KeyValueStorage = AppContext.shared.storage) {
        self.launchAtStartup = launchAtStartup
        self.alertPreferences = alertPreferences
        self.unitPreferences = unitPreferences
        self.storage = storage
        self.displayPreferences = MenuBarDisplayPreferences(storage: storage)
        self.panelTabPreferences = PanelTabPreferences(storage: storage)
        super.init(section: .general)
    }

    override func buildContent() {
        launchSwitch.target = self
        launchSwitch.action = #selector(launchChanged)
        launchSwitch.setAccessibilityLabel("开机自启动")
        alertSwitch.target = self
        alertSwitch.action = #selector(alertChanged)
        alertSwitch.setAccessibilityLabel("额度阈值提醒")

        unitControl.addItems(withTitles: NumberUnitStyle.allCases.map(\.title))
        unitControl.target = self
        unitControl.action = #selector(unitChanged)
        unitControl.setAccessibilityLabel("数值单位")

        launchRow.trailingStack.addArrangedSubview(launchSwitch)
        alertRow.trailingStack.addArrangedSubview(alertSwitch)
        unitRow.trailingStack.addArrangedSubview(unitControl)

        let launchCard = SettingsCardView()
        launchCard.addRow(launchRow)

        let alertCard = SettingsCardView()
        alertCard.addRow(alertRow)

        let unitCard = SettingsCardView()
        unitCard.addRow(unitRow)

        page.addCard(launchCard, sectionTitle: "启动")
        page.addCard(alertCard, sectionTitle: "额度提醒")
        page.addCard(unitCard, sectionTitle: "显示")

        buildOrderableCards()
        page.addNote("设置会立即生效；菜单栏指标与面板分页的顺序用行尾「上移 / 下移」调整，"
                     + "标题右侧可一键恢复默认。开机自启动依赖应用签名，未签名构建可能被系统拒绝。")
    }

    override func refresh() {
        launchSwitch.state = launchAtStartup.isEnabled ? .on : .off
        alertSwitch.state = alertPreferences.isEnabled ? .on : .off
        let style = unitPreferences.style
        let styleIndex = NumberUnitStyle.allCases.firstIndex(of: style) ?? 0
        unitControl.selectItem(at: styleIndex)
        unitRow.update(subtitle: style.detailText)
        launchRow.update(subtitle: launchAtStartup.isEnabled
                         ? "登录后自动启动 NetworkMonitor"
                         : "当前未登记开机自启动")
        refreshOrderableControls()
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

    /// 数值单位切档：写偏好（只写用户显式选择的档）→ 发事件让面板立刻重渲染
    @objc private func unitChanged() {
        let index = unitControl.indexOfSelectedItem
        guard NumberUnitStyle.allCases.indices.contains(index) else { return }
        let style = NumberUnitStyle.allCases[index]
        unitPreferences.setStyle(style)
        unitRow.update(subtitle: style.detailText)
        AppEvents.postNumberUnitStyleChanged()
    }
}
