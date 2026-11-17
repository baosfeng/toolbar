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

    // 状态枚举：暂停与停止是两个态（面板据此决定是否显示可恢复入口）
    assertEqual(ClipboardCaptureState.paused == ClipboardCaptureState.stopped, false, "暂停态与停止态可区分")
    assertEqual(ClipboardCaptureState.paused, ClipboardCaptureState.paused, "暂停态自反相等")

    print("✅ ClipboardPauseLogic works")
}
