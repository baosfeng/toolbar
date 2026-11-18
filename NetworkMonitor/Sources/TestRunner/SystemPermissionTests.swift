import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 系统权限状态机测试

/// 五类系统权限（辅助功能 / 屏幕录制 / 剪贴板访问 / 系统通知 / 开机自启动）的判定口径 —
/// 灯色 / 文案 / 标签 / 按钮 / 生效时机 / 找到应用的引导，全是纯规则。
///
/// 拆出 `ClipboardAccessTests.swift` 的原因：五类 × 六态的组合把断言撑到近三百行，
/// 与剪贴板五态混在一个文件会顶到单文件 15 KiB 上限。
func runSystemPermissionTests() {
    print("\n🧪 Testing 系统权限状态机...")

    // 五类权限与顺序（界面按这个顺序建行）
    assertEqual(SystemPermissionKind.allCases.count, 5, "五类权限")
    assertEqual(SystemPermissionKind.allCases.map(\.title),
                ["辅助功能", "屏幕录制", "剪贴板访问", "系统通知", "开机自启动"], "行名与顺序")
    assertEqual(SystemPermissionKind.allCases.map(\.settingsAnchor),
                ["Privacy_Accessibility", "Privacy_ScreenCapture", "Privacy",
                 "com.apple.Notifications-Settings.extension",
                 "com.apple.LoginItems-Settings.extension"],
                "系统设置锚点（单点出处）")
    assertEqual(SystemPermissionKind.allCases.filter(\.anchorsPrivacyPane),
                [.accessibility, .screenCapture, .clipboard],
                "只有三类隐私面板接在隐私与安全性之后")

    // 生效时机：只有屏幕录制要重启（TCC 缓存启动时读到的授权）
    assertEqual(SystemPermissionKind.screenCapture.requiresRestartAfterGrant, true,
                "屏幕录制授权后需重启")
    for kind in [SystemPermissionKind.accessibility, .clipboard, .notification, .loginItem] {
        assertEqual(kind.requiresRestartAfterGrant, false, "\(kind.rawValue) 即时生效")
    }

    // 有「系统设置清单」的两类才给找到应用的引导
    assertEqual(SystemPermissionKind.allCases.filter(\.supportsManualAdd),
                [.accessibility, .screenCapture], "只有两类隐私面板有清单")

    // 六态自身：文案与灯色
    assertEqual(SystemPermissionState.allCases.count, 6, "六种状态")
    assertEqual(SystemPermissionState.granted.label, "已授权", "已授权文案")
    assertEqual(SystemPermissionState.granted.tone, .ok, "已授权绿灯")
    assertEqual(SystemPermissionState.pending.label, "待授权", "待授权文案")
    assertEqual(SystemPermissionState.pending.tone, .warn, "待授权黄灯")
    assertEqual(SystemPermissionState.denied.label, "已关闭", "已关闭文案")
    assertEqual(SystemPermissionState.denied.tone, .warn, "已关闭黄灯")
    assertEqual(SystemPermissionState.unregistered.label, "未登记", "未登记文案")
    assertEqual(SystemPermissionState.unregistered.tone, .muted, "未登记灰灯")
    assertEqual(SystemPermissionState.unknown.tone, .muted, "未知灰灯")
    assertEqual(SystemPermissionState.checking.label, "检测中", "检测中文案")
    assertEqual(SystemPermissionState.checking.tone, .muted, "检测中灰灯")

    // 登录项 / 通知走系统侧自己的说法，其余沿用状态文案
    assertEqual(SystemPermissionKind.loginItem.label(for: .granted), "已登记", "登录项已登记")
    assertEqual(SystemPermissionKind.loginItem.label(for: .pending), "待批准", "登录项待批准")
    assertEqual(SystemPermissionKind.loginItem.label(for: .unregistered), "未登记", "登录项未登记")
    assertEqual(SystemPermissionKind.notification.label(for: .pending), "未授权", "通知未授权")
    assertEqual(SystemPermissionKind.accessibility.label(for: .granted), "已授权", "其余沿用状态文案")

    // 5 类 × 6 态：灯色 / 状态文案 / 标签 / 按钮显隐
    for kind in SystemPermissionKind.allCases {
        for state in SystemPermissionState.allCases {
            let entry = SystemPermissionEntry(kind: kind, state: state)
            assertEqual(entry.title, kind.title, "\(kind.rawValue)/\(state.rawValue) 行名")
            assertEqual(entry.label, kind.label(for: state),
                        "\(kind.rawValue)/\(state.rawValue) 状态文案")
            assertEqual(entry.tone, state.tone, "\(kind.rawValue)/\(state.rawValue) 灯色")
            assertEqual(entry.showsManualAddGuide, kind.supportsManualAdd && !state.isGranted,
                        "\(kind.rawValue)/\(state.rawValue) 找到应用的引导")
            assertEqual(entry.showsRestartHint, kind.requiresRestartAfterGrant && state.isGranted,
                        "\(kind.rawValue)/\(state.rawValue) 重启提示")
            assertEqual(entry.showsLoginItemSwitch, kind == .loginItem,
                        "\(kind.rawValue)/\(state.rawValue) 开关只在登录项")
            // 已授权时主按钮收起（屏幕录制例外：换成「重启应用」）
            if state.isGranted {
                assertEqual(entry.primaryAction, kind.requiresRestartAfterGrant ? .restartApp : nil,
                            "\(kind.rawValue) 已授权时的主动作")
            } else {
                assertNotNil(entry.primaryAction, "\(kind.rawValue)/\(state.rawValue) 未达标要有主动作")
            }
        }
    }

    // 标签：需重启 / 无请求 API / 登录项
    assertEqual(SystemPermissionEntry(kind: .screenCapture, state: .granted).tag, "需重启",
                "屏幕录制已授权打「需重启」")
    assertEqual(SystemPermissionEntry(kind: .screenCapture, state: .pending).tag, nil,
                "未授权不打「需重启」")
    assertEqual(SystemPermissionEntry(kind: .clipboard, state: .pending).tag, "无请求 API",
                "剪贴板访问无请求 API")
    assertEqual(SystemPermissionEntry(kind: .loginItem, state: .unregistered).tag, "登录项",
                "登录项行打「登录项」")

    // 主次按钮的具体落点
    assertEqual(SystemPermissionEntry(kind: .accessibility, state: .pending).primaryAction, .grant,
                "辅助功能未授权 → 授权")
    assertEqual(SystemPermissionEntry(kind: .clipboard, state: .pending).primaryAction, .openSettings,
                "剪贴板访问只能跳设置")
    assertEqual(SystemPermissionEntry(kind: .screenCapture, state: .granted).primaryAction, .restartApp,
                "屏幕录制已授权 → 重启应用")
    assertEqual(SystemPermissionEntry(kind: .notification, state: .pending).primaryAction, .grant,
                "通知未询问过 → 授权")
    assertEqual(SystemPermissionEntry(kind: .notification, state: .denied).primaryAction, .openSettings,
                "通知被关闭 → 打开系统设置")
    assertEqual(SystemPermissionEntry(kind: .loginItem, state: .unregistered).primaryAction, .openLoginItems,
                "登录项未登记 → 去登录项")
    assertEqual(SystemPermissionEntry(kind: .screenCapture, state: .pending).secondaryAction, .revealInFinder,
                "屏幕录制的次按钮是在 Finder 中显示")
    assertEqual(SystemPermissionEntry(kind: .notification, state: .pending).secondaryAction, nil,
                "通知没有次按钮")

    // 生效时机要写进副标题：辅助功能说「已生效」，屏幕录制说「重启后生效」
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .granted).detail, "已生效",
                   "辅助功能已授权写即时生效")
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .granted).detail, "无需重启",
                   "辅助功能明说不需重启")
    assertContains(SystemPermissionEntry(kind: .screenCapture, state: .granted).detail, "后生效",
                   "屏幕录制已授权写重启后生效")
    assertContains(SystemPermissionEntry(kind: .clipboard, state: .unknown).detail, "读不到",
                   "未知状态说明读不到")
    assertContains(SystemPermissionEntry(kind: .notification, state: .denied).detail, "已关闭",
                   "通知被关闭写已关闭")
    // 登录项回滚：有原因才写「已回滚为关」，没有原因只说未登记
    assertContains(SystemPermissionEntry(kind: .loginItem, state: .unregistered,
                                         rollbackReason: "系统拒绝").detail, "已回滚为关",
                   "登录项回滚要说明原因")
    assertEqual(SystemPermissionEntry(kind: .loginItem, state: .unregistered).detail.contains("已回滚"),
                false, "没发生过回滚不编原因")

    // 重启提示：屏幕录制已授权才给处置办法，读不到 / 未授权不猜
    assertContains(SystemPermissionEntry(kind: .screenCapture, state: .granted).restartHint, "重启",
                   "屏幕录制已授权提示重启")
    assertEqual(SystemPermissionEntry(kind: .screenCapture, state: .pending).restartHint, "",
                "未授权时不给重启提示（先授权再说）")
    assertEqual(SystemPermissionEntry(kind: .accessibility, state: .granted).restartHint, "",
                "辅助功能不提示重启")

    // 找到应用的引导：按中文名找 + 兜底手动添加，其余三类没有这条路径
    let appPath = "/Applications/一览.app"
    let guide = SystemPermissionEntry(kind: .screenCapture, state: .pending).manualAddGuide(appPath: appPath)
    assertContains(guide, "录屏与系统录音", "引导指明系统设置里的列表名")
    assertContains(guide, AppIdentity.displayName, "引导给出中文名（用户按它找）")
    assertContains(guide, appPath, "引导给出兜底添加路径")
    assertContains(SystemPermissionEntry(kind: .accessibility, state: .pending)
                    .manualAddGuide(appPath: appPath), "辅助功能", "辅助功能引导指明面板名")
    assertEqual(SystemPermissionEntry(kind: .clipboard, state: .pending).manualAddGuide(appPath: appPath), "",
                "剪贴板访问没有这条引导")
    assertEqual(SystemPermissionEntry(kind: .loginItem, state: .pending).manualAddGuide(appPath: appPath), "",
                "登录项没有这条引导")

    // 合计快照：计数 / 主语 / 灯色 / 是否需要注意
    let granted = SystemPermissionSnapshot(accessibility: .granted, screenCapture: .granted,
                                           clipboard: .granted, notification: .granted,
                                           loginItem: .granted)
    assertEqual(granted.grantedCount, 5, "全绿计数")
    assertEqual(granted.needsAttention, false, "全绿不需要处理")
    assertEqual(granted.summaryLabel, "权限 5/5 已授权", "全绿主语")
    assertEqual(granted.summaryTone, .ok, "全绿灯色")

    let mixed = SystemPermissionSnapshot(accessibility: .granted, screenCapture: .pending,
                                         clipboard: .unknown, notification: .denied,
                                         loginItem: .unregistered, loginItemRollbackReason: "系统拒绝")
    assertEqual(mixed.grantedCount, 1, "混合计数")
    assertEqual(mixed.pendingCount, 3, "待处理计数（待授权 + 已关闭 + 未登记）")
    assertEqual(mixed.summaryLabel, "权限 1/5 已授权", "混合主语")
    assertEqual(mixed.summaryTone, .warn, "有待处理即黄灯")
    assertEqual(mixed.needsAttention, true, "有待处理需要注意")
    assertEqual(mixed.state(for: .notification), .denied, "按类别取状态")
    assertEqual(mixed.entry(for: .loginItem).rollbackReason, "系统拒绝", "回滚原因随快照带出")

    let unknownFirst = SystemPermissionSnapshot(accessibility: .unknown, screenCapture: .unknown,
                                                clipboard: .unknown)
    assertEqual(unknownFirst.summaryLabel, "权限 0/5 已授权", "未读取时的主语")
    assertEqual(unknownFirst.summaryTone, .muted, "全未知用中性色")
    let checking = SystemPermissionSnapshot.allChecking
    assertEqual(checking.isAllChecking, true, "全部检测中")
    assertEqual(checking.summaryTone, .muted, "检测中用中性色")

    // 系统读数 → 权限状态
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .allowed), .granted, "已允许即已授权")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .denied), .denied, "被拒绝单列")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .ask), .pending, "每次询问算待授权")
    assertEqual(SystemPermissionSnapshot.clipboardState(from: .unknown), .unknown, "读不到即未知")
    assertEqual(SystemPermissionSnapshot.notificationState(from: .authorized), .granted, "通知已授权")
    assertEqual(SystemPermissionSnapshot.notificationState(from: .denied), .denied, "通知已关闭")
    assertEqual(SystemPermissionSnapshot.notificationState(from: .notDetermined), .pending,
                "通知未询问过算待授权")
    assertEqual(SystemPermissionSnapshot.loginItemState(from: .enabled), .granted, "登录项已登记")
    assertEqual(SystemPermissionSnapshot.loginItemState(from: .requiresApproval), .pending,
                "登录项待批准")
    assertEqual(SystemPermissionSnapshot.loginItemState(from: .notRegistered), .unregistered,
                "登录项未登记")
    assertEqual(SystemPermissionSnapshot.loginItemState(from: .notFound), .unregistered,
                "登录项未找到也按未登记")

    // 卡下说明：全绿只剩「切回即刷新 + 重启提示」；有待处理时补上引导与回滚警示
    let greenNotes = granted.notes(appPath: appPath)
    assertEqual(greenNotes.count, 2, "全绿：刷新说明 + 屏幕录制重启提示")
    assertEqual(greenNotes.allSatisfy { !$0.isEmpty }, true, "说明里没有空串")
    let mixedNotes = mixed.notes(appPath: appPath)
    assertContains(mixedNotes.joined(separator: "\n"), "一览", "说明里带中文名")
    assertContains(mixedNotes.joined(separator: "\n"), "已回滚", "登录项失败要写回滚警示")
    assertEqual(mixedNotes.contains { $0.contains("读不到") }, false, "未知状态不写进卡下说明")

    print("✅ 系统权限状态机 works")
}
