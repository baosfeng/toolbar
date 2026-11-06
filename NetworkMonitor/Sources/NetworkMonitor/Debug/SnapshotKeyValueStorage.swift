#if DEBUG
import Foundation
import NetworkMonitorCore

// MARK: - 快照专用存储（仅 DEBUG）

/// 内存键值存储 — 快照取证切档时用，进程退出即丢弃，绝不写用户真实偏好
///
/// 用途见 `MenuPanelSnapshot.unitStyleEnvKey`：`NM_UNIT_STYLE=chinese` 时把
/// `AppContext.shared.storage` 临时换成本实例并写入档位，出完图进程就退出。
final class SnapshotKeyValueStorage: KeyValueStorage, @unchecked Sendable {
    private var values: [String: Any] = [:]

    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func string(forKey key: String) -> String? { values[key] as? String }
    func object(forKey key: String) -> Any? { values[key] }
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }

    func set(_ value: Int, forKey key: String) { values[key] = value }
    func set(_ value: Double, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func set(_ value: Any?, forKey key: String) { values[key] = value }

    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
#endif
