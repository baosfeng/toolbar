import Foundation
import NetworkMonitorCore

// MARK: - 通知偏好与音效文件测试

/// 覆盖配置合并 / 恢复默认 / 旧键迁移、音效文件校验、
/// 自定义音效目录的文件操作（含路径穿越）与额度恢复评估
///
/// 与 NotificationTests.swift 分文件的原因：单文件 500 行 / 15 KiB 门禁，
/// 事件表与解析偏「口径」，这里偏「存储与文件」，两批断言互不依赖。
func runNotificationPreferenceTests() {
    print("\n🧪 Testing 通知偏好（合并 / 恢复默认 / 旧键迁移）...")
    testNotificationPreferences()

    print("\n🧪 Testing 音效文件校验与自定义音效目录...")
    testSoundFileValidation()
    testNotificationSoundFileStore()

    print("\n🧪 Testing 额度恢复评估...")
    testBillingRecovery()
}

// MARK: - 偏好

func testNotificationPreferences() {
    let storage = InMemoryStorage()
    let preferences = NotificationPreferences(storage: storage)

    // 未写过时全部取事件默认值
    let billing = preferences.config(for: .billingAlert)
    assertEqual(billing.enabled, true, "额度提醒默认开")
    assertEqual(billing.sound, .systemDefault, "默认跟随系统")
    assertEqual(billing.presentation, .bannerAndSound, "默认横幅+声音")
    assertEqual(preferences.inAppVolume, 1, "音量默认 1")

    // 写读一致
    preferences.setEnabled(false, for: .billingAlert)
    preferences.setSound(.systemSound("Pop"), for: .billingAlert)
    preferences.setPresentation(.notificationCenterOnly, for: .billingAlert)
    preferences.setHaptic(.strong, for: .billingAlert)
    let updated = preferences.config(for: .billingAlert)
    assertEqual(updated.enabled, false, "开关写入")
    assertEqual(updated.sound, .systemSound("Pop"), "声音写入")
    assertEqual(updated.presentation, .notificationCenterOnly, "提醒方式写入")
    assertEqual(updated.haptic, .strong, "触觉写入")
    // 别的行不受影响
    assertEqual(preferences.config(for: .transferFinished).sound, .systemDefault,
                "改一行不影响其它行")

    // 音量夹取
    preferences.inAppVolume = 2.5
    assertEqual(preferences.inAppVolume, 1, "音量上限 1")
    preferences.inAppVolume = -1
    assertEqual(preferences.inAppVolume, 0, "音量下限 0")
    preferences.inAppVolume = 1

    // 恢复默认
    preferences.resetToDefaults()
    let reset = preferences.config(for: .billingAlert)
    assertEqual(reset.enabled, true, "恢复默认回出厂开关")
    assertEqual(reset.sound, .systemDefault, "恢复默认回跟随系统")
    assertEqual(preferences.inAppVolume, 1, "恢复默认回满音量")

    // 旧剪贴板开关迁移：旧「操作音效」开着 → 新 clipboardAction 行跟着开
    let legacyStorage = InMemoryStorage()
    legacyStorage.set(true, forKey: NotificationPreferences.LegacyClipboardKey.soundEffects)
    legacyStorage.set(false, forKey: NotificationPreferences.LegacyClipboardKey.haptics)
    let migrated = NotificationPreferences(storage: legacyStorage)
    migrated.migrateLegacyClipboardFlagsIfNeeded()
    assertEqual(migrated.config(for: .clipboardAction).enabled, true, "旧音效开 → 迁移成开")
    assertEqual(migrated.config(for: .clipboardAction).haptic, .off, "旧触觉关 → 迁移成关")
    // 迁移只做一次：再改新值后重新迁移不覆盖
    migrated.setEnabled(false, for: .clipboardAction)
    migrated.migrateLegacyClipboardFlagsIfNeeded()
    assertEqual(migrated.config(for: .clipboardAction).enabled, false, "迁移只做一次，不覆盖用户新值")

    // 恢复默认后旧键不会再被迁回来
    migrated.resetToDefaults()
    migrated.migrateLegacyClipboardFlagsIfNeeded()
    assertEqual(migrated.config(for: .clipboardAction).enabled, false,
                "恢复默认后旧开关不会重新迁入")

    // 悬空引用自愈：自定义音效文件没了就回落「跟随系统」，还在的保持不动
    let heal = NotificationPreferences(storage: InMemoryStorage())
    heal.setSound(.customFile("在的.aiff"), for: .clipboardAction)
    heal.setSound(.customFile("没了的.aiff"), for: .snipCaptured)
    let repaired = heal.sanitizeCustomSoundReferences(availableFiles: ["在的.aiff"])
    assertEqual(repaired, [.snipCaptured], "只修真正缺文件的那一行")
    assertEqual(heal.config(for: .snipCaptured).sound, .systemDefault, "缺文件的行回落到跟随系统")
    assertEqual(heal.config(for: .clipboardAction).sound, .customFile("在的.aiff"),
                "还在的文件不受影响")
    assertEqual(heal.sanitizeCustomSoundReferences(availableFiles: ["在的.aiff"]), [],
                "再跑一遍无事可修")
}

// MARK: - 校验

func testSoundFileValidation() {
    // 路径穿越：只留最后一段
    assertEqual(SoundFileValidator.sanitizedDisplayName("../../etc/passwd"), "passwd",
                "路径穿越只留文件名")
    assertEqual(SoundFileValidator.sanitizedDisplayName("C:\\Windows\\evil.aiff"), "evil",
                "Windows 风格路径同样只留文件名")
    assertEqual(SoundFileValidator.sanitizedDisplayName(".."), nil, ".. 拒绝")
    assertEqual(SoundFileValidator.sanitizedDisplayName("  "), nil, "空白拒绝")
    assertEqual(SoundFileValidator.sanitizedDisplayName(".hidden.aiff"), nil, "隐藏文件拒绝")
    assertEqual(SoundFileValidator.sanitizedDisplayName("我的音效.wav"), "我的音效", "去扩展名")
    assertEqual(SoundFileValidator.sanitizedDisplayName(String(repeating: "a", count: 80))?.count,
                SoundFileValidator.maxNameLength, "超长截断")

    // 扩展名与体积
    assertEqual(SoundFileValidator.validate(fileName: "a.mp3", byteCount: 1024), nil, "mp3 允许")
    assertEqual(SoundFileValidator.validate(fileName: "a.aiff", byteCount: 1024), nil, "aiff 允许")
    assertEqual(SoundFileValidator.validate(fileName: "a.txt", byteCount: 1024), .unsupportedFormat,
                "txt 拒绝")
    assertEqual(SoundFileValidator.validate(fileName: "a.mp3", byteCount: 0), .unreadable, "空文件拒绝")
    assertEqual(SoundFileValidator.validate(fileName: "a.mp3",
                                            byteCount: SoundFileValidator.maxBytes + 1),
                .tooLarge, "超 10 MB 拒绝")
    assertEqual(SoundFileValidator.validate(fileName: "a.mp3",
                                            byteCount: SoundFileValidator.maxBytes),
                nil, "恰好 10 MB 允许")
}

// MARK: - 自定义音效目录

func testNotificationSoundFileStore() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nm-sound-store-\(UUID().uuidString)", isDirectory: true)
    let store = NotificationSoundFileStore(directory: root)
    defer { try? FileManager.default.removeItem(at: root) }

    // 造两份临时音频（内容不重要，Store 只管拷贝与命名）
    let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("nm-src-\(UUID().uuidString).aiff")
    try? Data(repeating: 0x41, count: 2048).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let first = try! store.importPreparedFile(from: source, displayName: "我的叮")
    assertEqual(first, "我的叮.aiff", "导入用清洗后的名字 + aiff 扩展名")
    assertEqual(store.files(), ["我的叮.aiff"], "目录里只有这一份")

    // 重名自动加序号
    let second = try! store.importPreparedFile(from: source, displayName: "我的叮")
    assertEqual(second, "我的叮 2.aiff", "重名加序号")

    // 路径穿越：名字清洗后落在自己目录内
    let traversal = try! store.importPreparedFile(from: source, displayName: "../../hack")
    assertEqual(traversal, "hack.aiff", "穿越名被清洗成普通文件名")
    assertEqual(store.files().contains("hack.aiff"), true, "文件落在自己目录内")
    assertEqual(store.url(for: "../../etc/passwd")?.path.hasPrefix(root.path), true,
                "url(for:) 永远在本目录内")

    // 重命名
    let renamed = try! store.rename("hack.aiff", to: "改好的名字")
    assertEqual(renamed, "改好的名字.aiff", "重命名保留 aiff 后缀")
    assertEqual(store.files().contains("hack.aiff"), false, "旧名消失")

    // 删除只删自己目录
    try! store.remove("改好的名字.aiff")
    assertEqual(store.files().contains("改好的名字.aiff"), false, "删除生效")
    assertEqual(store.totalBytes() > 0, true, "目录占用来算得出来")

    // 危险名一律拒绝（不抛就不是安全实现）
    var rejected = false
    do { _ = try store.importPreparedFile(from: source, displayName: "..") }
    catch { rejected = true }
    assertEqual(rejected, true, "非法名导入被拒")

    store.removeAll()
    assertEqual(store.files().isEmpty, true, "清空后目录为空")
}

// MARK: - 额度恢复

func testBillingRecovery() {
    let reset = Date(timeIntervalSince1970: 1_800_000_000)
    let period = BillingPeriod(start: reset.addingTimeInterval(-86_400),
                               end: reset.addingTimeInterval(86_400 * 20))
    func makeBalance(session: Double, resetAt: Date = Date(timeIntervalSince1970: 1_800_000_000))
        -> BillingBalance {
        BillingBalance(included: nil,
                       purchasedUSD: 10,
                       percentLimits: [
                        BillingPercentLimit(id: "session", title: "会话",
                                            remainingFraction: session, resetsAt: resetAt),
                       ])
    }
    _ = period

    // 跌破 → 提醒；回升 → 恢复；两者不重复
    let low = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.03),
                                             providerID: "p", state: [:])
    assertEqual(low.alerts.count, 1, "3% 发一条提醒")
    assertEqual(low.recoveries.isEmpty, true, "首次低额度不发恢复")
    let up = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.42),
                                            providerID: "p", state: low.state)
    assertEqual(up.alerts.isEmpty, true, "回升不发提醒")
    assertEqual(up.recoveries.count, 1, "回升发一条恢复")
    assertEqual(up.recoveries.first?.reason, .recovered, "恢复原因是回升")
    // 同一周期再涨一次不再发（状态已清）
    let again = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.5),
                                               providerID: "p", state: up.state)
    assertEqual(again.recoveries.isEmpty, true, "恢复只发一次")

    // 周期重置：换了 resetAt 且上周期提醒过 → 一条「周期重置」
    let nextCycle = BillingAlertEvaluator.evaluate(
        balance: makeBalance(session: 0.9, resetAt: Date(timeIntervalSince1970: 1_800_400_000)),
        providerID: "p", state: low.state)
    assertEqual(nextCycle.recoveries.count, 1, "周期重置发一条恢复")
    assertEqual(nextCycle.recoveries.first?.reason, .cycleReset, "恢复原因是周期重置")
    assertEqual(nextCycle.alerts.isEmpty, true, "重置后额度充足不发提醒")
}