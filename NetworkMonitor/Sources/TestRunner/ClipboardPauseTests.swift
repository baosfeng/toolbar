import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板暂停（纯口径）

/// 暂停的纯口径测试 —— 默认值 / 幂等判据 / 状态文案
///
/// 采集器本身在 App 目标（TestRunner 不可 import），因此这里断言的是它与界面共用的那份口径：
/// 默认未暂停、目标态等于当前态时不发生转换、三处可见文案随状态取不同值。
func runClipboardPauseTests() {
    print("🧪 Testing ClipboardPauseLogic...")

    // 偏好默认值：未写过键 = 未暂停（老用户升级后行为不变）
    assertEqual(ClipboardPauseLogic.isPaused(storedValue: nil), false, "未写入偏好时默认未暂停")
    assertEqual(ClipboardPauseLogic.isPaused(storedValue: true), true, "偏好为 true 时暂停")
    assertEqual(ClipboardPauseLogic.isPaused(storedValue: false), false, "偏好为 false 时未暂停")

    // 幂等判据：目标态与当前态相同则不做任何转换（重复点同态不会来回翻转）
    assertEqual(ClipboardPauseLogic.shouldTransition(currentlyPaused: false, target: true), true,
                "未暂停 → 暂停：需要转换")
    assertEqual(ClipboardPauseLogic.shouldTransition(currentlyPaused: true, target: false), true,
                "暂停 → 恢复：需要转换")
    assertEqual(ClipboardPauseLogic.shouldTransition(currentlyPaused: true, target: true), false,
                "已暂停再暂停：不转换（幂等）")
    assertEqual(ClipboardPauseLogic.shouldTransition(currentlyPaused: false, target: false), false,
                "未暂停再恢复：不转换（幂等）")

    // 提示行：暂停时常驻恢复入口，未暂停回到键位帮助
    let idleHint = "↑↓ 选择 / ⌘ 粘贴"
    let pausedHint = ClipboardPauseLogic.footerHint(isPaused: true, idleHint: idleHint)
    assertEqual(pausedHint.contains("采集已暂停"), true, "暂停文案包含「采集已暂停」")
    assertEqual(pausedHint.contains("恢复"), true, "暂停文案给出恢复入口")
    assertEqual(pausedHint.contains(ClipboardPauseLogic.toggleKeyHint), true, "暂停文案带出 ⌘P 键位")
    assertEqual(ClipboardPauseLogic.footerHint(isPaused: false, idleHint: idleHint), idleHint,
                "未暂停时原样回落到键位帮助")

    // 菜单与状态栏：同一状态给出可辨识的标题与前缀
    assertEqual(ClipboardPauseLogic.menuTitle(isPaused: true), "恢复采集", "暂停时菜单项为「恢复采集」")
    assertEqual(ClipboardPauseLogic.menuTitle(isPaused: false), "暂停采集", "未暂停时菜单项为「暂停采集」")
    assertEqual(ClipboardPauseLogic.statusPrefix(isPaused: true).isEmpty, false, "暂停时状态栏有可辨识前缀")
    assertEqual(ClipboardPauseLogic.statusPrefix(isPaused: false), "", "未暂停时状态栏不额外加前缀")

    // 异常路径：暂停时手动采集必须给可恢复提示，不得静默
    assertEqual(ClipboardPauseLogic.captureBlockedHint.contains("采集已暂停"), true,
                "暂停时手动采集提示说明原因")
    assertEqual(ClipboardPauseLogic.captureBlockedHint.contains(ClipboardPauseLogic.toggleKeyHint), true,
                "暂停时手动采集提示给出恢复键位")

    // 定时暂停：到点自动失效，手动暂停不过期
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let later = now.addingTimeInterval(15 * 60)
    assertEqual(ClipboardPauseLogic.isPausedNow(paused: false, pausedUntil: later, now: now), false,
                "未暂停时即便带定时也不算暂停")
    assertEqual(ClipboardPauseLogic.isPausedNow(paused: true, pausedUntil: .distantPast, now: now), true,
                "手动暂停（无定时）不会自己过期")
    assertEqual(ClipboardPauseLogic.isPausedNow(paused: true, pausedUntil: Date(timeIntervalSince1970: 0), now: now), true,
                "偏好缺失读出的时间戳 0 同样按手动暂停处理")
    assertEqual(ClipboardPauseLogic.isPausedNow(paused: true, pausedUntil: later, now: now), true,
                "定时未到的暂停态成立")
    assertEqual(ClipboardPauseLogic.isPausedNow(paused: true, pausedUntil: later, now: later), false,
                "定时到点即自动失效")
    assertEqual(ClipboardPauseLogic.isPausedNow(paused: true, pausedUntil: later, now: later.addingTimeInterval(60)), false,
                "定时已过仍判为未暂停（不因错过节拍而永久卡在暂停）")

    // 剩余分钟：向上取整，到点与无定时都归零
    assertEqual(ClipboardPauseLogic.remainingMinutes(pausedUntil: later, now: now), 15, "整 15 分钟")
    assertEqual(ClipboardPauseLogic.remainingMinutes(pausedUntil: now.addingTimeInterval(30), now: now), 1,
                "还剩 30 秒按 1 分钟计（不显示还剩 0 分钟）")
    assertEqual(ClipboardPauseLogic.remainingMinutes(pausedUntil: now.addingTimeInterval(59 * 60 + 1), now: now), 60,
                "59 分 1 秒向上取整为 60 分钟")
    assertEqual(ClipboardPauseLogic.remainingMinutes(pausedUntil: later, now: later), 0, "到点剩余 0 分钟")
    assertEqual(ClipboardPauseLogic.remainingMinutes(pausedUntil: .distantPast, now: now), 0, "无定时剩余 0 分钟")

    // 档位：三个预设换算成分钟，手动档不写截止时刻
    assertEqual(ClipboardPauseLogic.PauseDuration.fifteenMinutes.endDate(now: now), now.addingTimeInterval(900),
                "15 分钟档 = 900 秒后")
    assertEqual(ClipboardPauseLogic.PauseDuration.oneHour.endDate(now: now), now.addingTimeInterval(3600),
                "1 小时档 = 3600 秒后")
    assertEqual(ClipboardPauseLogic.PauseDuration.fourHours.endDate(now: now), now.addingTimeInterval(14400),
                "4 小时档 = 14400 秒后")
    assertEqual(ClipboardPauseLogic.PauseDuration.manual.endDate(now: now), .distantPast,
                "手动档不写定时截止时刻")

    // 提示行：定时暂停带出截止时刻（面板据此显示「暂停至 HH:mm」）
    let timedHint = ClipboardPauseLogic.footerHint(isPaused: true, pausedUntil: later, now: now, idleHint: idleHint)
    assertEqual(timedHint.contains("暂停至"), true, "定时暂停提示带出截止时刻")
    assertEqual(timedHint.contains(ClipboardPauseLogic.clockText(later)), true, "截止时刻用 HH:mm 口径")
    assertEqual(ClipboardPauseLogic.footerHint(isPaused: true, pausedUntil: .distantPast, now: now, idleHint: idleHint)
                .contains("暂停至"), false, "手动暂停不带截止时刻")

    // 状态枚举：暂停与停止是两个态（面板据此决定是否显示可恢复入口）
    assertEqual(ClipboardCaptureState.paused == ClipboardCaptureState.stopped, false, "暂停态与停止态可区分")
    assertEqual(ClipboardCaptureState.paused, ClipboardCaptureState.paused, "暂停态自反相等")

    print("✅ ClipboardPauseLogic works")
}
