import Foundation

// MARK: - 偏好域迁移（bundle id 变更）

/// 换 bundle id 时的偏好搬迁口径 —— 纯逻辑，TestRunner 可直接断言
///
/// 为什么需要它：macOS 把 `UserDefaults.standard` 落在
/// `~/Library/Preferences/<CFBundleIdentifier>.plist`。改 bundle id 等于换了一个偏好域，
/// 用户此前的全部设置（主题 / 分页顺序 / 快捷键 / 通知开关 / 额度阈值…）会在升级后
/// 「凭空消失、回到默认」——必须搬，而且必须幂等（每次启动都判断一遍）。
///
/// 口径：
/// - 只在「旧域有数据 + 当前域没有完成标记」时迁移；
/// - **不覆盖**当前域里已有的键（用户升级后已经改过的设置优先）；
/// - 迁移完写一条标记，之后每次启动直接跳过；
/// - 旧域**不删除**：留作回滚依据，且删了万一迁移有 bug 就彻底没了。
public enum PreferenceDomainMigration {

    /// 「已从旧 bundle id 迁移完成」的标记键
    public static let markerKey = "migration.preferencesFromLegacyBundleID"

    /// 迁移计划
    public struct Plan: Equatable {
        /// 需要从旧域复制过来的键（已排除当前域已有的与标记键自身）
        public let keysToCopy: [String]
        /// 当前域已有、因此跳过的键
        public let skippedExistingKeys: [String]
        /// 是否需要写完成标记
        public let shouldWriteMarker: Bool

        public init(keysToCopy: [String], skippedExistingKeys: [String], shouldWriteMarker: Bool) {
            self.keysToCopy = keysToCopy
            self.skippedExistingKeys = skippedExistingKeys
            self.shouldWriteMarker = shouldWriteMarker
        }

        /// 什么都不用做（已迁移过，或旧域为空）
        public var isNoop: Bool { keysToCopy.isEmpty && !shouldWriteMarker }
    }

    /// 制定迁移计划
    /// - Parameters:
    ///   - legacyKeys: 旧域的全部键
    ///   - currentKeys: 当前域的全部键
    ///   - alreadyMigrated: 当前域是否已有完成标记
    public static func plan(legacyKeys: [String],
                            currentKeys: [String],
                            alreadyMigrated: Bool) -> Plan {
        // 已迁移过：完全不动，连标记都不重写（避免每次都产生一次磁盘写入）
        if alreadyMigrated {
            return Plan(keysToCopy: [], skippedExistingKeys: [], shouldWriteMarker: false)
        }
        let current = Set(currentKeys)
        let legacy = legacyKeys.filter { $0 != markerKey }
        guard !legacy.isEmpty else {
            // 旧域为空（全新安装）：不写标记，下次启动再判断一次也无妨，
            // 免得「先装新版再装旧版」的用户丢掉后装那份的偏好
            return Plan(keysToCopy: [], skippedExistingKeys: [], shouldWriteMarker: false)
        }
        let toCopy = legacy.filter { !current.contains($0) }.sorted()
        let skipped = legacy.filter { current.contains($0) }.sorted()
        return Plan(keysToCopy: toCopy, skippedExistingKeys: skipped, shouldWriteMarker: true)
    }
}
