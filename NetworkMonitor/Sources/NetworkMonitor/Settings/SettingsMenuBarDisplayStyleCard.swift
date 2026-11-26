import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 菜单栏显示方式设置卡

/// 菜单栏显示方式卡 —— 模板 / 密度 / 单位 / **标签** / 布局 + 逐项自定义入口
///
/// 从 `SettingsGeneralPane+Ordering.swift` 拆出：本卡的行数与控件数已超过
/// 「三张卡挤一个文件」的量，且它自带逐项自定义弹窗，单独成卡更贴项目的卡片范式
/// （同 `SettingsMenuBarAlertCard`：构建 / 回灌 / 动作全在文件内，调用方只 addCard + refresh）。
///
/// 「标签」是本轮新增：用户口径是「直接展示 Token 等很大的标识，太浪费空间」。
/// 档位只有完整 / 短标签两档（不做「只显示图标」——见 `MenuBarLabelStyle` 的注释），
/// 逐项自定义优先级最高，缺省值一律回落到接入本偏好之前的硬编码前缀，老用户外观不变。
@MainActor
final class SettingsMenuBarDisplayStyleCard {

    /// 卡片本体 —— 调用方 `page.addCard(card.card, sectionTitle: "菜单栏显示方式")`
    let card = SettingsCardView()

    private let preferences: MenuBarDisplayPreferences
    /// 写偏好之后的回调（调用方在这里发 `AppEvents.postMenuBarDisplayChanged`）
    private let onChange: () -> Void
    /// 模板切换后的回调：模板会改「显示哪些指标」，而指标开关在另一张卡里，
    /// 本卡够不着，由页面在这里回灌（不与 `onChange` 合并：后者只管菜单栏重画）
    var onTemplateChange: (() -> Void)?
    /// 逐项自定义弹窗的宿主窗口（弹窗挂在设置窗口上，不另起模态会话）
    var windowProvider: (() -> NSWindow?)?

    // MARK: - 控件

    let templateControl = NSSegmentedControl(labels: SettingsGeneralPane.templateTitles,
                                              trackingMode: .selectOne,
                                              target: nil,
                                              action: nil)
    let densityControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let unitControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let labelControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let layoutControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let customRow = SettingsRowView(title: "逐项自定义",
                                    subtitle: "给任意一项换前缀（如把「Token 」换成「T 」）")
    let customButton = NSButton(title: "编辑…", target: nil, action: nil)

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
        let templateRow = SettingsRowView(title: "快捷模板",
                                          subtitle: "只改显示哪些指标，不改「菜单栏指标」卡里排好的顺序")
        templateControl.target = self
        templateControl.action = #selector(templateChanged)
        templateControl.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: templateControl)
        templateRow.trailingStack.addArrangedSubview(templateControl)
        card.addRow(templateRow)

        configure(densityControl, titles: MenuBarDensity.allCases.map(\.rawValue),
                  accessibility: "菜单栏密度", action: #selector(densityChanged))
        card.addRow(rows("密度", control: densityControl))

        // 菜单栏单位档：custom 目前没有自定义单位表（按 short 回落），
        // 直接标在标题里，避免用户选了「自定义」却看不到任何变化
        configure(unitControl, titles: MenuBarUnitStyle.allCases.map(\.title),
                  accessibility: "菜单栏单位", action: #selector(unitChanged))
        unitRow.trailingStack.addArrangedSubview(unitControl)
        card.addRow(unitRow)

        // 标签档：完整 / 短标签，副标题写出当前档的真实写法
        configure(labelControl, titles: MenuBarLabelStyle.allCases.map(\.title),
                  accessibility: "菜单栏标签", action: #selector(labelChanged))
        labelRow.trailingStack.addArrangedSubview(labelControl)
        card.addRow(labelRow)

        configure(layoutControl, titles: MenuBarLayout.allCases.map(\.rawValue),
                  accessibility: "菜单栏布局", action: #selector(layoutChanged))
        card.addRow(rows("布局", control: layoutControl))

        customButton.target = self
        customButton.action = #selector(editCustomLabels)
        customButton.bezelStyle = .rounded
        customButton.setAccessibilityLabel("逐项自定义菜单栏前缀")
        customRow.trailingStack.addArrangedSubview(customButton)
        card.addRow(customRow)
    }

    private let unitRow = SettingsRowView(title: "单位")
    private let labelRow = SettingsRowView(title: "标签")

    private func rows(_ title: String, control: NSPopUpButton) -> SettingsRowView {
        let row = SettingsRowView(title: title)
        row.trailingStack.addArrangedSubview(control)
        return row
    }

    private func configure(_ control: NSPopUpButton, titles: [String],
                           accessibility: String, action: Selector) {
        control.addItems(withTitles: titles)
        control.target = self
        control.action = action
        control.setAccessibilityLabel(accessibility)
        control.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: control)
    }

    // MARK: - 刷新

    /// 按偏好灌控件（设置页每次进入 / 恢复默认后都要重画，文案随档位变）
    func refresh() {
        templateControl.selectedSegment = SettingsGeneralPane.templateNames.firstIndex(of: preferences.template) ?? -1
        if let i = MenuBarDensity.allCases.firstIndex(of: preferences.density) { densityControl.selectItem(at: i) }
        if let i = MenuBarUnitStyle.allCases.firstIndex(of: preferences.unitStyle) { unitControl.selectItem(at: i) }
        if let i = MenuBarLabelStyle.allCases.firstIndex(of: preferences.labelStyle) { labelControl.selectItem(at: i) }
        if let i = MenuBarLayout.allCases.firstIndex(of: preferences.layout) { layoutControl.selectItem(at: i) }
        unitRow.update(subtitle: SettingsGeneralPane.menuBarUnitSubtitle(preferences.unitStyle))
        labelRow.update(subtitle: preferences.labelStyle.detailText)
        let custom = preferences.customLabels.count
        customRow.update(subtitle: custom == 0
                         ? "写当前档的默认前缀；改哪一项就只影响哪一项"
                         : "已自定义 \(custom) 项")
    }

    // MARK: - 动作

    @objc private func templateChanged() {
        let index = templateControl.selectedSegment
        guard SettingsGeneralPane.templateNames.indices.contains(index) else { return }
        preferences.applyTemplate(SettingsGeneralPane.templateNames[index])
        onTemplateChange?()
        onChange()
    }

    @objc private func densityChanged() {
        guard MenuBarDensity.allCases.indices.contains(densityControl.indexOfSelectedItem) else { return }
        preferences.density = MenuBarDensity.allCases[densityControl.indexOfSelectedItem]
        onChange()
    }

    @objc private func unitChanged() {
        guard MenuBarUnitStyle.allCases.indices.contains(unitControl.indexOfSelectedItem) else { return }
        preferences.unitStyle = MenuBarUnitStyle.allCases[unitControl.indexOfSelectedItem]
        unitRow.update(subtitle: SettingsGeneralPane.menuBarUnitSubtitle(preferences.unitStyle))
        onChange()
    }

    @objc private func labelChanged() {
        guard MenuBarLabelStyle.allCases.indices.contains(labelControl.indexOfSelectedItem) else { return }
        preferences.labelStyle = MenuBarLabelStyle.allCases[labelControl.indexOfSelectedItem]
        labelRow.update(subtitle: preferences.labelStyle.detailText)
        onChange()
    }

    @objc private func layoutChanged() {
        guard MenuBarLayout.allCases.indices.contains(layoutControl.indexOfSelectedItem) else { return }
        preferences.layout = MenuBarLayout.allCases[layoutControl.indexOfSelectedItem]
        onChange()
    }

    /// 打开逐项自定义弹窗：保存后重灌本卡副标题并发事件让菜单栏立刻重画
    @objc private func editCustomLabels() {
        let editor = SettingsMenuBarLabelEditor(preferences: preferences) { [weak self] in
            self?.refresh()
            self?.onChange()
        }
        editor.present(sheetParent: windowProvider?())
    }
}
