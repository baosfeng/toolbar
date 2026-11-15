import Foundation
import NetworkMonitorCore

// MARK: - 偏好域迁移执行器（App 侧）

/// 把「旧 bundle id 偏好域」搬进当前域的**执行器**
///
/// 纯判定在 `PreferenceDomainMigration`（Core，可断言）；本文件只负责真正的
/// `UserDefaults` 读写与日志，两段分开是为了让「该不该迁、迁哪些」有测试守。
///
/// 调用点：`AppDelegate.applicationDidFinishLaunching` 的**最前面**（早于任何读偏好的服务），
/// 否则早期服务读到默认值后写回，迁移判定会看到「当前域已有键」而跳过。
enum PreferenceDomainMigrator {

    /// 旧 bundle id（迁移来源）
    static let legacyBundleIdentifier = "com.example.NetworkMonitor"

    /// 执行迁移，返回迁移了多少键（0 = 无需迁移或失败）
    @discardableResult
    static func runIfNeeded(currentBundleIdentifier: String?) -> Int {
        guard let current = currentBundleIdentifier,
              current != legacyBundleIdentifier else { return 0 }
        let currentDefaults = UserDefaults.standard
        guard let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier) else { return 0 }

        let plan = PreferenceDomainMigration.plan(
            legacyKeys: Array(legacyDefaults.dictionaryRepresentation().keys),
            currentKeys: Array(currentDefaults.dictionaryRepresentation().keys),
            alreadyMigrated: currentDefaults.bool(forKey: PreferenceDomainMigration.markerKey))
        guard !plan.isNoop else { return 0 }

        var copied = 0
        for key in plan.keysToCopy where legacyDefaults.object(forKey: key) != nil {
            currentDefaults.set(legacyDefaults.object(forKey: key), forKey: key)
            copied += 1
        }
        if plan.shouldWriteMarker {
            currentDefaults.set(true, forKey: PreferenceDomainMigration.markerKey)
        }
        AppContext.shared.logger.info(
            "偏好域迁移完成：\(legacyBundleIdentifier) → \(current)，复制 \(copied) 项，"
            + "跳过已存在 \(plan.skippedExistingKeys.count) 项")
        return copied
    }
}
