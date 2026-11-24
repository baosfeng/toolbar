import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 系统监控设置页

/// 系统监控设置 — 面板显示项（采样节拍不在这里）
///
/// 偏好一律走 Core 的 SystemMonitorPreferences（禁止直读 UserDefaults）：
/// 温度开关在面板每次渲染时读取，切回面板即生效（v4 起控制底部状态带的温度段，不再是独立卡片）。
///
/// **采样周期行已下线**：那个偏好键只喂 SystemMonitor(interval:)，而 SystemMonitor.start()
/// 从不被调用（采样由 MenuBarManager 的轮询链驱动、节拍取自渲染档），
/// 所以它是个改了完全没反应的死开关，副标题「重启应用后生效」也是错的。
/// 节拍与菜单栏刷新共用一个旋钮：外观 → 渲染帧率。
final class SettingsSystemPane: SettingsPaneView {

    private let preferences: SystemMonitorPreferences

    // v4 起温度卡已下线：温度并进底部状态带，开关语义随之变成「状态带里的温度是否显示」
    private let thermalRow = SettingsRowView(title: "显示 SoC 温度",
                                             subtitle: "温度读数走 IOHID 事件字段，显示在面板底部状态带，默认开启")

    private let thermalSwitch = NSSwitch()

    init(preferences: SystemMonitorPreferences = SystemMonitorPreferences()) {
        self.preferences = preferences
        super.init(section: .system)
    }

    override func buildContent() {
        thermalSwitch.target = self
        thermalSwitch.action = #selector(thermalChanged)
        thermalSwitch.setAccessibilityLabel("显示 SoC 温度")

        thermalRow.trailingStack.addArrangedSubview(thermalSwitch)

        let panelCard = SettingsCardView()
        panelCard.addRow(thermalRow)

        page.addCard(panelCard, sectionTitle: "面板")
        page.addNote("系统指标在菜单栏面板的「系统」分段查看。采样节拍由「外观 → 渲染帧率」统一决定"
                     + "（标准 1 秒 / 极致 0.5 秒 / 省电 3 秒），与菜单栏刷新节拍同一份档位。")
    }

    override func refresh() {
        thermalSwitch.state = preferences.isPanelItemVisible(.thermal) ? .on : .off
        refreshStatusChip()
    }

    /// 页头胶囊：实际生效的采样节拍（取渲染档，不取那个已下线的偏好键）
    ///
    /// 显示真值而不是「用户填过的值」：采样节拍由渲染档接管，页头必须与面板实际节拍一致。
    private func refreshStatusChip() {
        let tier = AppearancePreferences().renderTier
        let seconds = String(format: "%.1f", RenderTierLogic.profile(for: tier).sampleInterval)
        page.setStatusChip(SettingsStatusChip(subject: "采样 \(seconds) s", tone: .muted))
    }

    // MARK: - 动作

    @objc private func thermalChanged() {
        let visible = thermalSwitch.state == .on
        preferences.setPanelItemVisible(visible, for: .thermal)
        thermalRow.update(subtitle: visible ? "状态带会显示 SoC 温度" : "状态带不显示温度")
        // 温度段在系统页渲染时读取偏好：发事件让面板下一拍就重画，不必等 5 秒闸门
        AppEvents.postMenuBarDisplayChanged()
    }
}
