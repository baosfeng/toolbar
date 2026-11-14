import AppKit

// MARK: - 剪贴板设置页（操作反馈）

/// 操作反馈 — 音效与触觉两个开关
///
/// 拆出原因：主文件已贴着单文件 15 KiB 上限，且这两项共用同一组「写偏好即生效」逻辑。
/// 跨文件访问：`soundEffectsSwitch` / `hapticsSwitch` / `preferences` 由主文件放宽为 internal。
///
/// 口径（设计规格 §3 B3 / B4）：操作音效默认关闭、触觉反馈默认开启；
/// 两个服务每次调用现读偏好，这里改完立即生效，不需要额外的回调通知。
extension SettingsClipboardPane {

    /// 构建「操作反馈」卡片（声效 + 触觉）
    func buildFeedbackCard() {
        soundEffectsSwitch.target = self
        soundEffectsSwitch.action = #selector(soundEffectsChanged)
        soundEffectsSwitch.setAccessibilityLabel("操作音效")

        hapticsSwitch.target = self
        hapticsSwitch.action = #selector(hapticsChanged)
        hapticsSwitch.setAccessibilityLabel("触觉反馈")

        let soundRow = SettingsRowView(title: "操作音效",
                                       subtitle: "复制、粘贴、收藏、删除时播放系统提示音，默认关闭")
        soundRow.trailingStack.addArrangedSubview(soundEffectsSwitch)
        let hapticRow = SettingsRowView(title: "触觉反馈",
                                        subtitle: "卡片选中与收藏时给出触控板反馈，默认开启")
        hapticRow.trailingStack.addArrangedSubview(hapticsSwitch)

        let card = SettingsCardView()
        [soundRow, hapticRow].forEach(card.addRow)
        page.addCard(card, sectionTitle: "操作反馈")

        // 构建完立刻按偏好灌一次：首次进页与离屏快照都不保证走到 refresh 的切页分支，
        // 不灌就会出现「偏好是开、控件画成关」的假象（见踩坑记录「离屏快照看不出开关状态」）
        refreshFeedbackSwitches()
    }

    /// 同步两个开关的显示状态（切页 / 窗口重新显示时调用）
    func refreshFeedbackSwitches() {
        soundEffectsSwitch.state = preferences.soundEffectsEnabled ? .on : .off
        hapticsSwitch.state = preferences.hapticsEnabled ? .on : .off
    }

    @objc func soundEffectsChanged() {
        preferences.soundEffectsEnabled = soundEffectsSwitch.state == .on
    }

    @objc func hapticsChanged() {
        preferences.hapticsEnabled = hapticsSwitch.state == .on
    }

    #if DEBUG
    /// 仅 DEBUG：把「操作反馈」两个开关的控件勾选态与偏好真值并排落盘，用于核对「界面显示 vs 实际配置」
    ///
    /// 离屏快照里 NSSwitch 的 on/off 几乎不可辨（见 docs/踩坑/运行时/离屏快照看不出开关状态.md），
    /// 状态判定以这份文本为准：`偏好真值/控件勾选态`，两者不一致说明是 refresh 时序问题而不是渲染问题。
    func debugLogFeedbackControlStates(_ tag: String) {
        let soundPref = preferences.soundEffectsEnabled
        let hapticsPref = preferences.hapticsEnabled
        let soundState = soundEffectsSwitch.state == .on
        let hapticsState = hapticsSwitch.state == .on
        let matches = soundPref == soundState && hapticsPref == hapticsState
        let line = "[\(tag)] sound=\(soundPref)/\(soundState ? "on" : "off") "
            + "haptics=\(hapticsPref)/\(hapticsState ? "on" : "off") 一致=\(matches)"
        guard let path = ProcessInfo.processInfo.environment["NM_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("settings-clipboard-states.txt")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif
}
