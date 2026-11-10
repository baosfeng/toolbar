import Foundation
import NetworkMonitorCore

// MARK: - 截图快捷键偏好读写（回归：keyCode = 0 的合法组合曾被判为「未设置」）
//
// 复现链路：偏好里存 `snip.hotKey.screenshot.keyCode = 0` + `modifiers = 2304`（⌘⌥A），
// 旧实现用 `guard code > 0` 判存在性 → 读成「未设置」→ 回落 ⌃⇧S → 注册成功后把默认值写回
// → 用户自定义被永久覆盖（「自定义了下次又被还原」）。
// 键名与判据都收敛在 Core 的 SnipHotKeyKeyNames / SnipHotKeyComboResolver，测试直接断言。

func runSnipHotKeyPreferencesTests() {
    print("\n🧪 Testing snip hotkey preferences...")

    let sourceAction = "screenshot"
    let keyCodeKey = SnipHotKeyKeyNames.keyCodeKey(actionRawValue: sourceAction)
    let modifiersKey = SnipHotKeyKeyNames.modifiersKey(actionRawValue: sourceAction)
    // 默认组合取 Core 侧的等价裸值：⌃⇧S = keyCode 1 (kVK_ANSI_S) + 4096 | 512
    let fallback = SnipHotKeyComboValue(keyCode: 1, modifiers: 4096 | 512)
    let commandOptionA = SnipHotKeyComboValue(keyCode: 0, modifiers: 2304)

    // 1) 回归：keyCode 就是 0（A 键）时按存储的原值读回，不许回落默认
    do {
        let storage = InMemoryStorage()
        storage.set(0, forKey: keyCodeKey)
        storage.set(2304, forKey: modifiersKey)
        let resolution = SnipHotKeyComboResolver.resolve(storage: storage,
                                                         keyCodeKey: keyCodeKey,
                                                         modifiersKey: modifiersKey,
                                                         fallback: fallback)
        assertEqual(resolution.combo, commandOptionA, "keyCode 0 + ⌘⌥ 修饰键必须原样读回（A 键 keyCode 就是 0）")
        assertEqual(resolution.usedFallback, false, "存储里有键就不算回落")
        assertEqual(resolution.didMigrate, false, "⌘⌥A 不在旧默认值白名单，不迁移")
    }

    // 2) 复现用户抱怨：同一个存储连读两次，第二次必须还是第一次的结果（不能被回落/迁移改掉）
    do {
        let storage = InMemoryStorage()
        storage.set(0, forKey: keyCodeKey)
        storage.set(2304, forKey: modifiersKey)
        let first = SnipHotKeyComboResolver.resolve(storage: storage,
                                                    keyCodeKey: keyCodeKey,
                                                    modifiersKey: modifiersKey,
                                                    fallback: fallback)
        let second = SnipHotKeyComboResolver.resolve(storage: storage,
                                                     keyCodeKey: keyCodeKey,
                                                     modifiersKey: modifiersKey,
                                                     fallback: fallback)
        assertEqual(second.combo, first.combo, "连读两次结果必须一致（自定义不得被读路径还原）")
        assertEqual(storage.integer(forKey: keyCodeKey), 0, "读路径不得把 keyCode 写回成默认值")
        assertEqual(storage.integer(forKey: modifiersKey), 2304, "读路径不得把 modifiers 写回成默认值")
    }

    // 3) 键确实不存在 → 回落默认组合，且**不写回**默认值
    do {
        let storage = InMemoryStorage()
        let resolution = SnipHotKeyComboResolver.resolve(storage: storage,
                                                         keyCodeKey: keyCodeKey,
                                                         modifiersKey: modifiersKey,
                                                         fallback: fallback)
        assertEqual(resolution.combo, fallback, "未设置过时必须回落默认组合")
        assertEqual(resolution.usedFallback, true, "未设置过要标记 usedFallback")
        assertEqual(resolution.didMigrate, false, "未设置过不触发迁移")
        assertEqual(storage.object(forKey: keyCodeKey) == nil, true, "读路径不得给缺失的键补写默认值")
        assertEqual(storage.object(forKey: modifiersKey) == nil, true, "读路径不得给缺失的键补写默认值")
    }

    // 4) 只有一个键存在（另一个缺失）同样按未设置处理：两个键都必须在
    do {
        let storage = InMemoryStorage()
        storage.set(0, forKey: keyCodeKey)
        let resolution = SnipHotKeyComboResolver.resolve(storage: storage,
                                                         keyCodeKey: keyCodeKey,
                                                         modifiersKey: modifiersKey,
                                                         fallback: fallback)
        assertEqual(resolution.usedFallback, true, "缺 modifiers 键时按未设置回落")
        assertEqual(resolution.combo, fallback, "缺 modifiers 键时返回默认组合")
    }

    // 5) 迁移仍生效：无修饰键的 F1（122）/ F3（99）一次性换成新默认值，并回写一次后稳定
    do {
        let storage = InMemoryStorage()
        storage.set(122, forKey: keyCodeKey)
        storage.set(0, forKey: modifiersKey)
        let resolution = SnipHotKeyComboResolver.resolve(storage: storage,
                                                         keyCodeKey: keyCodeKey,
                                                         modifiersKey: modifiersKey,
                                                         fallback: fallback)
        assertEqual(resolution.combo, SnipHotKeyComboValue(keyCode: 1, modifiers: 4096 | 512), "F1 旧默认值迁移为 ⌃⇧S")
        assertEqual(resolution.didMigrate, true, "命中旧默认值白名单要标记 didMigrate（供调用方回写一次）")

        // 迁移结果回写后，第二次读必须稳定在同一结果（幂等，不会反复迁移）
        storage.set(Int(resolution.combo.keyCode), forKey: keyCodeKey)
        storage.set(Int(resolution.combo.modifiers), forKey: modifiersKey)
        let second = SnipHotKeyComboResolver.resolve(storage: storage,
                                                     keyCodeKey: keyCodeKey,
                                                     modifiersKey: modifiersKey,
                                                     fallback: fallback)
        assertEqual(second.combo, resolution.combo, "迁移回写后再读结果不变（幂等）")
        assertEqual(second.didMigrate, false, "已迁移过的值不再触发迁移")

        // F3（99）同样走白名单迁移：旧默认值 → ⌃⇧V（keyCode 9 + 4096 | 512）
        let storageF3 = InMemoryStorage()
        storageF3.set(99, forKey: keyCodeKey)
        storageF3.set(0, forKey: modifiersKey)
        let resolutionF3 = SnipHotKeyComboResolver.resolve(storage: storageF3,
                                                           keyCodeKey: keyCodeKey,
                                                           modifiersKey: modifiersKey,
                                                           fallback: fallback)
        assertEqual(resolutionF3.combo, SnipHotKeyComboValue(keyCode: 9, modifiers: 4096 | 512),
                    "F3 旧默认值迁移为 ⌃⇧V")
        assertEqual(resolutionF3.didMigrate, true, "F3 迁移要标记 didMigrate")
    }

    // 6) 负数损坏值（偏好被外部改坏）不能直接转 UInt32（会 trapping），按未设置回落
    do {
        let storage = InMemoryStorage()
        storage.set(-1, forKey: keyCodeKey)
        storage.set(2304, forKey: modifiersKey)
        let resolution = SnipHotKeyComboResolver.resolve(storage: storage,
                                                         keyCodeKey: keyCodeKey,
                                                         modifiersKey: modifiersKey,
                                                         fallback: fallback)
        assertEqual(resolution.combo, fallback, "负数键码按未设置回落，不得崩溃")
        assertEqual(resolution.usedFallback, true, "负数键码标记为回落")
    }

    // 7) 各动作的键名互不串键（白名单显式列举，不靠前缀撞运气）
    do {
        let rawValues = ["screenshot", "pin", "delayedScreenshot", "hidePins", "settings", "whiteboard"]
        for raw in rawValues {
            assertEqual(SnipHotKeyKeyNames.keyCodeKey(actionRawValue: raw),
                        "snip.hotKey.\(raw).keyCode", "键码键名规则")
            assertEqual(SnipHotKeyKeyNames.modifiersKey(actionRawValue: raw),
                        "snip.hotKey.\(raw).modifiers", "修饰键键名规则")
        }
        assertEqual(Set(rawValues.map { SnipHotKeyKeyNames.keyCodeKey(actionRawValue: $0) }).count,
                    rawValues.count, "六个动作的键码键名互不相同")
    }

    print("✅ 截图快捷键偏好读写测试通过")
}
