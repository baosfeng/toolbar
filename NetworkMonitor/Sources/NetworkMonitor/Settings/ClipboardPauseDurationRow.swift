import AppKit
import NetworkMonitorUI

// MARK: - 定时暂停时长选择

/// 剪贴板设置页「暂停采集」旁的时长下拉 —— 选中即按该时长进入暂停
///
/// 独立成视图的原因：设置页族已顶到同族门禁基线，时长档位的展示与回显收在这一处，
/// 页面只保留「取值 + 一个回调」。档位口径与截止时刻换算都在 `ClipboardPauseLogic`（纯函数）。
@MainActor
final class ClipboardPauseDurationRow: NSObject {

    /// 下拉本体（页面直接摆到暂停行里）
    let popup = NSPopUpButton()

    /// 用户选中某个档位（页面据此让采集器按该时长暂停）
    var onSelect: ((ClipboardPauseLogic.PauseDuration) -> Void)?

    override init() {
        super.init()
        popup.controlSize = .small
        popup.font = SettingsTheme.rowTitleFont
        for duration in ClipboardPauseLogic.PauseDuration.allCases {
            popup.addItem(withTitle: duration.label)
            popup.lastItem?.representedObject = duration.rawValue
        }
        popup.target = self
        popup.action = #selector(selectionChanged)
        popup.widthAnchor.constraint(equalToConstant: 118).isActive = true
        popup.setAccessibilityLabel("暂停时长")
        SettingsControlChrome.applyStandardHeight(to: popup)
    }

    /// 回显当前档位：暂停中且剩余分钟数正好命中某档时选中它，其余情况落「到手动恢复」
    ///
    /// 不按截止时刻反推原始档位的时长：用户可能在设置页外改过偏好，
    /// 按剩余时间匹配能保证回显与实际生效的暂停一致。
    func refresh(pausedUntil: Date, now: Date = Date()) {
        let remaining = ClipboardPauseLogic.remainingMinutes(pausedUntil: pausedUntil, now: now)
        let matched = ClipboardPauseLogic.PauseDuration.allCases.first { $0.rawValue == remaining }
        let duration = matched ?? .manual
        popup.selectItem(at: ClipboardPauseLogic.PauseDuration.allCases.firstIndex(of: duration) ?? 0)
    }

    @objc private func selectionChanged() {
        guard let raw = popup.selectedItem?.representedObject as? Int,
              let duration = ClipboardPauseLogic.PauseDuration(rawValue: raw) else { return }
        onSelect?(duration)
    }
}
