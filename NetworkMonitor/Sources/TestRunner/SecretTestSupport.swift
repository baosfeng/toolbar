import Foundation
import NetworkMonitorCore

// MARK: - 凭据测试替身

/// 内存秘密存储 — 单测不往真实钥匙串写垃圾（会污染本机钥匙串、测试互相干扰）
final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    private(set) var values: [String: String] = [:]

    /// 测试替身模拟「独立存储」（钥匙串形态），搬迁逻辑因此会生效
    var sharesStorageWithPreferences: Bool { false }

    func secret(forKey key: String) -> String? { values[key] }

    func setSecret(_ value: String?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}
