import AppKit
import NetworkMonitorCore

// MARK: - 通用设置页

/// 通用设置 —— 启动行为、额度提醒、数值单位，以及可自定义排序的
/// 「菜单栏指标 / 面板分页 / 菜单栏显示方式」三块（排序构建与刷新拆在 +Ordering.swift）
///
/// 开关类写进既有偏好实现（`LaunchAtStartupService` / `BillingAlertPreferences`），
/// 开机自启动的显示态读**系统登记态**（`LaunchAtStartupService.registration`），
/// 偏好键只是「用户意图」的本地记录 —— 与系统权限页、面板菜单同一份判据。
/// 「数值单位」写 `NumberUnitPreferences`（Core），切档后发 `AppEvents.numberUnitStyleChanged`，
/// 菜单面板据此立即重渲染，不用重启。
///
/// 「面板展开收起」的通知行放本页：面板行为归通用，它的声音与触觉也跟着通用设置走。
final class SettingsGeneralPane: SettingsPaneView, SettingsNotificationEventHosting {

    private let launchAtStartup: LaunchAtStartupService
    private let alertPreferences: BillingAlertPreferences
    private let unitPreferences: NumberUnitPreferences
    /// 鼠标滚轮平滑设置卡（可选模块，默认关闭；写偏好即热生效）
    private let smoothScrollCard: SettingsSmoothScrollCard
    /// 面板展开收起通知行（放宽为 internal：DEBUG 快照要按协议取到它）
    let notificationCard: SettingsNotificationEventCard
    private let launchRow = SettingsRowView(title: "开机自启动",
                                            subtitle: "登录后自动启动 \(AppIdentity.displayName)")
    private let alertRow = SettingsRowView(title: "额度用尽提醒",
                                           subtitle: "额度剩余跌破用尽线（默认 1%）时发送，5% 起先发预告")
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

    /// - Parameters:
    ///   - smoothScrollStateText: 引擎当前状态说明（组合根注入；读不到时按关闭态显示）
    ///   - onSmoothScrollChange: 写平滑偏好之后的回调（组合根让引擎热生效）
    init(launchAtStartup: LaunchAtStartupService = LaunchAtStartupService(),
         alertPreferences: BillingAlertPreferences = BillingAlertPreferences(),
         unitPreferences: NumberUnitPreferences = NumberUnitPreferences(),
         storage: any KeyValueStorage = AppContext.shared.storage,
         smoothScrollStateText: @escaping () -> String = { "未启用" },
         onSmoothScrollChange: @escaping () -> Void = {},
         notificationContext: SettingsNotificationEventContext) {
        self.launchAtStartup = launchAtStartup
        self.alertPreferences = alertPreferences
        self.unitPreferences = unitPreferences
        self.smoothScrollCard = SettingsSmoothScrollCard(
            settings: SmoothScrollSettings(storage: storage),
            stateText: smoothScrollStateText,
            onChange: onSmoothScrollChange)
        self.notificationCard = SettingsNotificationEventCard(events: [.panelToggle],
                                                              context: notificationContext)
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
        alertSwitch.setAccessibilityLabel("额度用尽提醒")

        unitControl.addItems(withTitles: NumberUnitStyle.allCases.map(\.title))
        unitControl.target = self
        unitControl.action = #selector(unitChanged)
        unitControl.setAccessibilityLabel("数值单位")
        unitControl.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: unitControl)

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
        page.addCard(smoothScrollCard.card, sectionTitle: "鼠标滚轮")
        page.addCard(notificationCard.card, sectionTitle: "通知与音效")

        buildOrderableCards()
        page.addNote("设置会立即生效；菜单栏指标与面板分页的顺序用行尾「上移 / 下移」调整，"
                     + "标题右侧可一键恢复默认。开机自启动依赖应用签名，未签名构建可能被系统拒绝。")
    }

    /// 按系统登记态刷开关与副标题（显示口径在 UI 库 LaunchItemPresentation，本页只落控件）
    private func applyLaunchState() {
        let presentation = launchAtStartup.presentation
        launchSwitch.state = presentation.isOn ? .on : .off
        launchRow.update(subtitle: presentation.subtitle)
    }

    override func refresh() {
        applyLaunchState()
        alertSwitch.state = alertPreferences.isEnabled ? .on : .off
        let style = unitPreferences.style
        let styleIndex = NumberUnitStyle.allCases.firstIndex(of: style) ?? 0
        unitControl.selectItem(at: styleIndex)
        unitRow.update(subtitle: style.detailText)
        smoothScrollCard.refresh()
        notificationCard.refresh()
        refreshOrderableControls()
    }

#if DEBUG
    /// 取证：鼠标滚轮平滑卡的控件态与偏好真值（离屏快照看不出勾选态）
    func debugLogSmoothScrollStates(_ tag: String) {
        smoothScrollCard.debugLogStates(tag)
    }
#endif

    // MARK: - 动作

    /// 开机自启动切换：失败时服务已回滚偏好并把原因记进 lastFailureReason，
    /// 界面一律按系统登记态重画（显示口径在 UI 库 LaunchItemPresentation）
    @objc private func launchChanged() {
        launchAtStartup.setEnabled(launchSwitch.state == .on)
        applyLaunchState()
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
