import Foundation
import NetworkMonitorCore

// MARK: - 通知与音效测试

/// 覆盖事件表映射与声音解析（偏好 / 文件 / 额度恢复见 NotificationPreferenceTests.swift）
func runNotificationTests() {
    print("\n🧪 Testing 通知事件表与声音解析...")
    testNotificationEventTable()
    testNotificationSoundResolution()

    // 偏好 / 校验 / 目录 / 额度恢复在 NotificationPreferenceTests.swift
    runNotificationPreferenceTests()

    print("✅ 通知与音效 works")
}

// MARK: - 事件表

private func testNotificationEventTable() {
    assertEqual(NotificationEvent.allCases.count, 7, "事件表七行（额度三类各一行 + 截图 / 剪贴板 / 传输 / 面板）")
    assertEqual(NotificationEvent.billingAlert.postsSystemNotification, true, "额度提醒发系统通知")
    assertEqual(NotificationEvent.transferFinished.postsSystemNotification, true, "传输完成发系统通知")
    assertEqual(NotificationEvent.clipboardAction.postsSystemNotification, false, "剪贴板动作只有应用内提示音")
    assertEqual(NotificationEvent.panelToggle.postsSystemNotification, false, "面板展开收起只有应用内提示音")
    assertEqual(NotificationEvent.billingAlert.defaultEnabled, true, "额度提醒默认开")
    assertEqual(NotificationEvent.clipboardAction.defaultEnabled, false, "剪贴板音效默认关（既有口径）")
    assertEqual(NotificationEvent.clipboardAction.defaultHaptic, .standard, "触觉默认标准（既有口径默认开）")
    assertEqual(NotificationEvent.panelToggle.defaultHaptic, .off, "面板展开默认不震")

    // cue → 事件是多对一：五个剪贴板 cue 都落在 clipboardAction
    let clipboardCues: [NotificationCue] = [.copy, .paste, .pin, .delete, .error]
    assertEqual(clipboardCues.allSatisfy { $0.event == .clipboardAction }, true,
                "五个剪贴板 cue 归属 clipboardAction")
    assertEqual(NotificationCue.panelToggle.event, .panelToggle, "面板 cue 归属自己的事件")
    assertEqual(NotificationCue.snipCapture.event, .snipCaptured, "截图 cue 归属截图事件")
    // 每个 cue 都有默认系统音，且系统音都在内置清单里
    for cue in NotificationCue.allCases {
        assertNotNil(SystemSoundCatalog.builtIn.first { $0.name == cue.defaultSystemSound },
                     "cue \(cue.rawValue) 的默认音 \(cue.defaultSystemSound) 在系统音效清单内")
    }
}

// MARK: - 声音解析

private func testNotificationSoundResolution() {
    // 跟随系统：应用内用 cue 经典音，而不是通知的系统默认音
    assertEqual(NotificationSoundResolver.cueSound(selection: .systemDefault, cue: .copy),
                .system("Tink"), "跟随系统 → 复制用 Tink")
    assertEqual(NotificationSoundResolver.cueSound(selection: .systemDefault, cue: .error),
                .system("Basso"), "跟随系统 → 失败用 Basso")
    // 选了具体系统音：五个 cue 统一用它
    assertEqual(NotificationSoundResolver.cueSound(selection: .systemSound("Glass"), cue: .error),
                .system("Glass"), "指定系统音覆盖 cue 默认")
    assertEqual(NotificationSoundResolver.cueSound(selection: .customFile("mine.aiff"), cue: .copy),
                .customFile("mine.aiff"), "自定义文件优先生效")
    assertEqual(NotificationSoundResolver.cueSound(selection: .silent, cue: .copy), nil, "静音不播")

    // 系统通知：提醒方式没有「声音」档时必须静音
    let installed: (NotificationSoundSelection) -> String? = { selection in
        switch selection {
        case .systemSound(let name): return "NetworkMonitor-sys-\(name).aiff"
        case .customFile(let file): return "NetworkMonitor-custom-\(file).aiff"
        case .systemDefault, .silent: return nil
        }
    }
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .systemSound("Glass"),
                                                           presentation: .bannerAndSound,
                                                           installedName: installed),
                .named("NetworkMonitor-sys-Glass.aiff"), "横幅+声音 → 指定音效")
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .systemSound("Glass"),
                                                           presentation: .bannerOnly,
                                                           installedName: installed),
                .silent, "仅横幅 → 通知静音")
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .systemSound("Glass"),
                                                           presentation: .notificationCenterOnly,
                                                           installedName: installed),
                .silent, "仅通知中心 → 通知静音")
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .systemDefault,
                                                           presentation: .bannerAndSound,
                                                           installedName: installed),
                .systemDefault, "跟随系统 → 通知用系统默认音")
    // 装不进通知目录（系统里没有这个音名）时回落系统默认音，而不是静默失败
    assertEqual(NotificationSoundResolver.notificationPlan(selection: .systemSound("NoSuchSound"),
                                                           presentation: .bannerAndSound,
                                                           installedName: { _ in nil }),
                .systemDefault, "装不上就回落系统默认音")

    // 存储值往返
    for selection: NotificationSoundSelection in [.systemDefault, .systemSound("Ping"),
                                                  .customFile("x.aiff"), .silent] {
        assertEqual(NotificationSoundSelection(storageValue: selection.storageValue), selection,
                    "存储值往返：\(selection.storageValue)")
    }
    assertEqual(NotificationSoundSelection(storageValue: "脏数据"), .systemDefault,
                "脏数据回落跟随系统")
    assertEqual(NotificationPresentation.allCases.count, 3, "提醒方式三档（系统允许的组合）")
    assertEqual(NotificationPresentation.bannerOnly.includesSound, false, "仅横幅不含声音")
    assertEqual(NotificationHaptic.allCases.count, 4, "触觉四档（关/轻/标准/有力）")
}

