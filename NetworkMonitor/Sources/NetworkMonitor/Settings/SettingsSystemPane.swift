import AppKit
import NetworkMonitorCore

// MARK: - 系统监控设置页

/// 系统监控设置 — 采样周期与面板显示项
///
/// 偏好一律走 Core 的 `SystemMonitorPreferences`（禁止直读 UserDefaults）：
/// 采样周期在组合根按该值构造采样服务，修改后重启应用生效；
/// 温度卡开关在面板每次渲染时读取，切回面板即生效。
final class SettingsSystemPane: SettingsPaneView {

    private let preferences: SystemMonitorPreferences

    private let intervalRow = SettingsRowView(title: "采样周期",
                                              subtitle: "系统指标采样间隔，修改后重启应用生效")
    private let thermalRow = SettingsRowView(title: "面板显示温度卡",
                                             subtitle: "温度来自 SMC 私有接口，默认关闭")
    private let intervalControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let thermalSwitch = NSSwitch()

    /// 下拉选项与对应秒数（Core 允许区间 0.5...5.0）
    private static let intervalOptions: [(title: String, value: TimeInterval)] = [
        ("0.5 秒", 0.5),
        ("1 秒", 1),
        ("2 秒", 2),
        ("5 秒", 5),
    ]

    init(preferences: SystemMonitorPreferences = SystemMonitorPreferences()) {
        self.preferences = preferences
        super.init(section: .system)
    }

    override func buildContent() {
        intervalControl.addItems(withTitles: Self.intervalOptions.map { $0.title })
        intervalControl.target = self
        intervalControl.action = #selector(intervalChanged)
        intervalControl.setAccessibilityLabel("采样周期")

        thermalSwitch.target = self
        thermalSwitch.action = #selector(thermalChanged)
        thermalSwitch.setAccessibilityLabel("面板显示温度卡")

        intervalRow.trailingStack.addArrangedSubview(intervalControl)
        thermalRow.trailingStack.addArrangedSubview(thermalSwitch)

        let sampleCard = SettingsCardView()
        sampleCard.addRow(intervalRow)
        let panelCard = SettingsCardView()
        panelCard.addRow(thermalRow)

        page.addCard(sampleCard, sectionTitle: "采样")
        page.addCard(panelCard, sectionTitle: "面板")
        page.addNote("系统指标在菜单栏面板的「系统」分段查看；采样周期越短越实时，采样开销也越高。")
    }

    override func refresh() {
        let current = preferences.sampleInterval
        // 取与当前值最接近的选项（偏好可能来自更早版本的其他数值）
        let index = Self.intervalOptions.enumerated()
            .min { abs($0.element.value - current) < abs($1.element.value - current) }?
            .offset ?? 1
        intervalControl.selectItem(at: index)
        thermalSwitch.state = preferences.isPanelItemVisible(.thermal) ? .on : .off
    }

    // MARK: - 动作

    @objc private func intervalChanged() {
        let index = intervalControl.indexOfSelectedItem
        guard Self.intervalOptions.indices.contains(index) else { return }
        let option = Self.intervalOptions[index]
        preferences.sampleInterval = option.value
        intervalRow.update(subtitle: "当前 \(option.title)，重启应用后生效")
    }

    @objc private func thermalChanged() {
        let visible = thermalSwitch.state == .on
        preferences.setPanelItemVisible(visible, for: .thermal)
        thermalRow.update(subtitle: visible ? "面板会显示温度卡" : "面板不显示温度卡")
    }
}
