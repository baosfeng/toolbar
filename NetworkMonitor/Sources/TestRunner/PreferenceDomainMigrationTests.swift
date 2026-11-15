import Foundation
import NetworkMonitorCore

// MARK: - 偏好域迁移（bundle id 变更时的设置搬迁）
//
// 存在理由：macOS 把 UserDefaults.standard 落在 ~/Library/Preferences/<bundleID>.plist。
// 换 bundle id 等于换了偏好域，用户此前的主题 / 分页顺序 / 快捷键 / 通知开关 / 额度阈值
// 会在升级后「凭空回到默认」。纯判定在 PreferenceDomainMigration，本文件守它的口径：
// 只迁一次（幂等）、不覆盖当前域已有键、旧域为空时安全跳过。

private func testMigrationCopiesAllKeysWhenCurrentEmpty() {
    let plan = PreferenceDomainMigration.plan(
        legacyKeys: ["theme", "panel.tabs", "hotkey.clipboard", "migration.preferencesFromLegacyBundleID"],
        currentKeys: [],
        alreadyMigrated: false)
    assertEqual(plan.keysToCopy, ["hotkey.clipboard", "panel.tabs", "theme"], "迁全部键，且排除标记键自身")
    assertEqual(plan.skippedExistingKeys, [], "没有已存在的键")
    assertEqual(plan.shouldWriteMarker, true, "首次迁移要写标记")
    assertEqual(plan.isNoop, false, "有键要迁就不是 noop")
}

private func testMigrationIsIdempotent() {
    let plan = PreferenceDomainMigration.plan(
        legacyKeys: ["theme", "panel.tabs"],
        currentKeys: ["theme", "migration.preferencesFromLegacyBundleID"],
        alreadyMigrated: true)
    assertEqual(plan.keysToCopy, [], "已迁移过就不再迁任何键")
    assertEqual(plan.shouldWriteMarker, false, "已迁移过不重复写标记")
    assertEqual(plan.isNoop, true, "已迁移过是 noop")
}

private func testMigrationSkipsExistingKeys() {
    let plan = PreferenceDomainMigration.plan(
        legacyKeys: ["theme", "panel.tabs", "hotkey.clipboard"],
        currentKeys: ["theme"],
        alreadyMigrated: false)
    assertEqual(plan.keysToCopy, ["hotkey.clipboard", "panel.tabs"], "只补当前域没有的键")
    assertEqual(plan.skippedExistingKeys, ["theme"], "当前域已有的键要记下来（用户升级后改过的优先）")
    assertEqual(plan.shouldWriteMarker, true, "迁完要写标记")
}

private func testMigrationSkipsWhenLegacyEmpty() {
    let plan = PreferenceDomainMigration.plan(legacyKeys: [], currentKeys: ["theme"], alreadyMigrated: false)
    assertEqual(plan.keysToCopy, [], "旧域为空不迁任何键")
    assertEqual(plan.isNoop, true, "全新安装是 noop")
    assertEqual(plan.shouldWriteMarker, false,
                "旧域为空时不写标记：先装新版再装旧版的用户不该丢掉后装那份的偏好")
}

private func testMigrationOnlyMarkerInLegacy() {
    let plan = PreferenceDomainMigration.plan(
        legacyKeys: ["migration.preferencesFromLegacyBundleID"],
        currentKeys: [],
        alreadyMigrated: false)
    assertEqual(plan.keysToCopy, [], "旧域只有标记键时视为空")
    assertEqual(plan.isNoop, true, "只有标记键是 noop")
}

func runPreferenceDomainMigrationTests() {
    testMigrationCopiesAllKeysWhenCurrentEmpty()
    testMigrationIsIdempotent()
    testMigrationSkipsExistingKeys()
    testMigrationSkipsWhenLegacyEmpty()
    testMigrationOnlyMarkerInLegacy()
    print("✓ 偏好域迁移（全量搬迁 / 幂等 / 跳过已有 / 旧域为空 / 仅标记键）")
}
