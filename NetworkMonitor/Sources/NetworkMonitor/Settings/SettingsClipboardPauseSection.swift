import AppKit
import NetworkMonitorCore

// MARK: - 暂停采集行

/// 设置页「暂停采集」一行 —— 开关 + 时长选择同一处装配与回显
///
/// 独立成文件（族名前缀与设置页族不同）：暂停行是开关与定时两套语义的汇合点，
/// 收在一处才不会让设置页本体再长一截；档位换算仍走 `ClipboardPauseLogic` 纯函数。
@MainActor
final class ClipboardPauseSection {

    private let preferences: ClipboardPreferences
    private weak var delegate: ClipboardSettingsDelegate?
    private let toggle = NSSwitch()
    private let durationRow = ClipboardPauseDurationRow()

    init(preferences: ClipboardPreferences, delegate: ClipboardSettingsDelegate?) {
        self.preferences = preferences
        self.delegate = delegate
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("暂停采集")
        durationRow.onSelect = { [weak self] duration in self?.apply(duration) }
    }

    /// 把两个控件摆进设置行（时长在前、开关在后：开关是状态，时长是动作）
    func attach(to row: SettingsRowView) {
        row.trailingStack.addArrangedSubview(durationRow.popup)
        row.trailingStack.addArrangedSubview(toggle)
    }

    /// 从偏好回读：定时暂停到点后开关要自动落回关，不能停留在旧快照
    func refresh() {
        toggle.state = preferences.isPausedNow ? .on : .off
        durationRow.refresh(pausedUntil: preferences.pausedUntil)
    }

    /// 开关动作：动作为「目标态」，实现幂等，重复点同态不会把状态翻回去
    @objc private func toggleChanged() {
        delegate?.settingsDidChangePause(toggle.state == .on)
        // 回读真源（暂停在轮询模式下会连带停采集，设置页显示不能与采集器脱节）
        refresh()
    }

    /// 选中时长即进入暂停；切回「到手动恢复」只清定时，暂停继续（不自动恢复）
    private func apply(_ duration: ClipboardPauseLogic.PauseDuration) {
        delegate?.settingsDidChangeTimedPause(until: duration.endDate(now: Date()))
        refresh()
    }
}
