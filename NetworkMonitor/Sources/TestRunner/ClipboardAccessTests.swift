import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板访问状态测试

/// 剪贴板访问权限的文案 / 色调 / 是否跳系统设置 — 纯规则，不依赖 AppKit
func runClipboardAccessTests() {
    print("\n🧪 Testing 剪贴板访问状态...")

    assertEqual(ClipboardAccessState.allCases.count, 5, "五种状态（allow/deny/ask/unspecified/unknown）")

    assertEqual(ClipboardAccessState.allowed.label, "已允许", "已允许文案")
    assertEqual(ClipboardAccessState.allowed.tone, .ok, "已允许为正常色调")
    assertEqual(ClipboardAccessState.allowed.needsSettingsJump, false, "已允许不显示跳转")

    assertEqual(ClipboardAccessState.denied.label, "已被拒绝", "拒绝文案")
    assertEqual(ClipboardAccessState.denied.tone, .warning, "拒绝为需处理色调")
    assertEqual(ClipboardAccessState.denied.needsSettingsJump, true, "拒绝时要能跳系统设置")

    assertEqual(ClipboardAccessState.ask.label, "每次询问", "每次询问文案")
    assertEqual(ClipboardAccessState.ask.tone, .warning, "每次询问为需处理色调")
    assertEqual(ClipboardAccessState.ask.needsSettingsJump, true, "每次询问时可跳转")

    assertEqual(ClipboardAccessState.unspecified.label, "默认", "系统默认文案")
    assertEqual(ClipboardAccessState.unspecified.tone, .muted, "系统默认用弱化色调")
    assertEqual(ClipboardAccessState.unspecified.needsSettingsJump, true, "系统默认可跳转")

    assertEqual(ClipboardAccessState.unknown.label, "未知", "低版本文案")
    assertEqual(ClipboardAccessState.unknown.tone, .muted, "未知用弱化色调")

    print("✅ 剪贴板访问状态 works")
}
// MARK: - 系统权限状态机测试

/// 三类系统权限（辅助功能 / 屏幕录制 / 剪贴板访问）的三态映射 —
/// 灯色 / 文案 / 生效时机 / 找到应用的引导，全是纯规则
func runSystemPermissionTests() {
    print("\n🧪 Testing 系统权限状态机...")

    // 三类权限与顺序（界面按这个顺序建行）
    assertEqual(SystemPermissionKind.allCases.count, 3, "三类权限")
    assertEqual(SystemPermissionKind.allCases.map(\.title), ["辅助功能", "屏幕录制", "剪贴板访问"],
                "行名与顺序")
    assertEqual(SystemPermissionKind.allCases.map(\.settingsAnchor),
                ["Privacy_Accessibility", "Privacy_ScreenCapture", "Privacy"],
                "系统设置深链锚点")

    // 生效时机：只有屏幕录制要重启（TCC 缓存启动时读到的授权）
    assertEqual(SystemPermissionKind.screenCapture.requiresRestartAfterGrant, true,
                "屏幕录制授权后需重启")
    assertEqual(SystemPermissionKind.accessibility.requiresRestartAfterGrant, false,
                "辅助功能同一进程即时生效")
    assertEqual(SystemPermissionKind.clipboard.requiresRestartAfterGrant, false,
                "剪贴板访问即时生效")

    // 有「系统设置清单」的两类才给找到应用的引导
    assertEqual(SystemPermissionKind.accessibility.supportsManualAdd, true, "辅助功能有清单")
    assertEqual(SystemPermissionKind.screenCapture.supportsManualAdd, true, "屏幕录制有清单")
    assertEqual(SystemPermissionKind.clipboard.supportsManualAdd, false, "剪贴板访问无清单")

    // 三态自身：文案与灯色
    assertEqual(SystemPermissionState.allCases.count, 3, "三态")
    assertEqual(SystemPermissionState.granted.label, "已授权", "已授权文案")
    assertEqual(SystemPermissionState.granted.tone, .ok, "已授权绿灯")
    assertEqual(SystemPermissionState.pending.label, "待授权", "待授权文案")
    assertEqual(SystemPermissionState.pending.tone, .warn, "待授权黄灯")
    assertEqual(SystemPermissionState.unknown.label, "未知", "未知文案")
    assertEqual(SystemPermissionState.unknown.tone, .muted, "未知灰灯")

    // 3 类 × 3 态：按钮显隐 / 引导 / 重启提示
    for kind in SystemPermissionKind.allCases {
        for state in SystemPermissionState.allCases {
            let entry = SystemPermissionEntry(kind: kind, state: state)
            assertEqual(entry.title, kind.title, "\(kind.rawValue)/\(state.rawValue) 行名")
            assertEqual(entry.label, state.label, "\(kind.rawValue)/\(state.rawValue) 状态文案")
            assertEqual(entry.tone, state.tone, "\(kind.rawValue)/\(state.rawValue) 灯色")
            assertEqual(entry.showsGrantAction, state != .granted,
                        "\(kind.rawValue)/\(state.rawValue) 授权按钮只在未授权时显示")
            assertEqual(entry.showsManualAddGuide, kind.supportsManualAdd && state != .granted,
                        "\(kind.rawValue)/\(state.rawValue) 找到应用的引导")
            assertEqual(entry.showsRestartHint, kind.requiresRestartAfterGrant && state != .unknown,
                        "\(kind.rawValue)/\(state.rawValue) 重启提示")
        }
    }

    // 生效时机要写进副标题：辅助功能说「已生效」，屏幕录制说「重启后生效」
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .granted).detail, "已生效",
                   "辅助功能已授权写即时生效")
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .granted).detail, "无需重启",
                   "辅助功能明说不需重启")
    assertNotContains(SystemPermissionEntry(kind: .accessibility, state: .granted).detail, "重启 app 后生效",
                      "辅助功能不写「重启后才生效」")
    assertContains(SystemPermissionEntry(kind: .screenCapture, state: .granted).detail, "重启 app 后生效",
                   "屏幕录制已授权写重启后生效")
    assertContains(SystemPermissionEntry(kind: .screenCapture, state: .pending).detail, "需重启",
                   "屏幕录制未开启也预告重启")
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .pending).detail, "即生效",
                   "辅助功能未开启写打开即生效")
    assertContains(SystemPermissionEntry(kind: .clipboard, state: .unknown).detail, "读不到",
                   "未知状态说明读不到")

    // 重启提示：屏幕录制勾没勾都要给处置办法，读不到时不猜
    assertContains(SystemPermissionEntry(kind: .screenCapture, state: .pending).restartHint, "重启",
                   "屏幕录制待授权要给重启提示")
    assertContains(SystemPermissionEntry(kind: .screenCapture, state: .granted).restartHint, "重启",
                   "屏幕录制已授权同样提示重启")
    assertEqual(SystemPermissionEntry(kind: .screenCapture, state: .unknown).restartHint, "",
                "读不到状态不提示重启")
    assertEqual(SystemPermissionEntry(kind: .accessibility, state: .pending).restartHint, "",
                "辅助功能不提示重启")

    // 找到应用的引导：按中文名找 + 兜底手动添加，剪贴板访问没有这条路径
    let appPath = "/Applications/一览.app"
    let guide = SystemPermissionEntry(kind: .screenCapture, state: .pending).manualAddGuide(appPath: appPath)
    assertContains(guide, "录屏与系统录音", "引导指明系统设置里的列表名")
    assertContains(guide, AppIdentity.displayName, "引导给出中文名（用户按它找）")
    assertContains(guide, appPath, "引导给出兜底添加路径")
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .pending)
                    .manualAddGuide(appPath: appPath), "辅助功能", "辅助功能引导指明面板名")
    assertEqual(SystemPermissionEntry(kind: .clipboard, state: .pending).manualAddGuide(appPath: appPath), "",
                "剪贴板访问没有这条引导")

    // 合计快照：计数 / 主语 / 灯色 / 是否需要注意
    let granted = SystemPermissionSnapshot(accessibility: .granted, screenCapture: .granted, clipboard: .granted)
    assertEqual(granted.grantedCount, 3, "全绿计数")
    assertEqual(granted.needsAttention, false, "全绿不需要处理")
    assertEqual(granted.summaryLabel, "权限 3/3 已授权", "全绿主语")
    assertEqual(granted.summaryTone, .ok, "全绿灯色")

    let mixed = SystemPermissionSnapshot(accessibility: .granted, screenCapture: .pending, clipboard: .unknown)
    assertEqual(mixed.grantedCount, 1, "混合计数")
    assertEqual(mixed.pendingCount, 1, "待授权计数")
    assertEqual(mixed.summaryLabel, "权限 1/3 已授权", "混合主语")
    assertEqual(mixed.summaryTone, .warn, "有待授权即黄灯")
    assertEqual(mixed.needsAttention, true, "有待授权需要注意")
    assertEqual(mixed.entries.count, 3, "三类各一条")
    assertEqual(mixed.state(for: .screenCapture), .pending, "按类别取状态")
    assertEqual(mixed.entry(for: .clipboard).state, .unknown, "按类别取口径")

    let allUnknown = SystemPermissionSnapshot.allUnknown
    assertEqual(allUnknown.summaryLabel, "权限 0/3 已授权", "未读取时的主语")
    assertEqual(allUnknown.summaryTone, .muted, "全未知用中性色")
    let pendingFirst = SystemPermissionSnapshot(accessibility: .unknown, screenCapture: .pending, clipboard: .unknown)
    assertEqual(pendingFirst.summaryTone, .warn, "待授权优先于未知")

    // 剪贴板五态 → 权限三态：只有「已允许」达标
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .allowed), .granted, "已允许即已授权")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .denied), .pending, "被拒绝算待授权")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .ask), .pending, "每次询问算待授权")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .unspecified), .pending, "系统默认算待授权")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .unknown), .unknown, "读不到即未知")

    // 卡下说明的拼装：全绿只剩「切回即刷新 + 重启提示」；待授权时补上找到应用的引导
    let greenNotes = granted.notes(appPath: appPath)
    assertEqual(greenNotes.count, 2, "全绿：刷新说明 + 屏幕录制重启提示")
    assertEqual(greenNotes.allSatisfy { !$0.isEmpty }, true, "说明里没有空串")
    // mixed = 辅助功能已授权 / 屏幕录制待授权 / 剪贴板未知：
    // 刷新说明 + 屏幕录制的「找到应用」引导 + 屏幕录制的重启提示（已授权的辅助功能不再给引导）
    let pendingNotes = mixed.notes(appPath: appPath)
    assertEqual(pendingNotes.count, 3, "待授权：刷新说明 + 一条引导 + 一条重启提示")
    assertContains(pendingNotes.joined(separator: "\n"), "一览", "说明里带中文名")

    print("✅ 系统权限状态机 works")
}
