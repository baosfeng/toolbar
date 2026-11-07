import Foundation
import Security

// MARK: - 秘密存储协议

/// 秘密存储 — 凭据这类「可直接冒用」的内容一律走这里，不走键值偏好
///
/// 抽成协议的原因：单测不能往真实 Keychain 里写垃圾（会污染本机钥匙串，
/// 也让测试互相干扰），测试注入内存实现即可。
public protocol SecretStorage: AnyObject, Sendable {
    /// 读取（无则 nil）
    func secret(forKey key: String) -> String?
    /// 写入（nil = 删除）
    func setSecret(_ value: String?, forKey key: String)
}

// MARK: - Keychain 实现

/// Keychain 实现 — 凭据落在登录钥匙串，不再以明文写在 ~/Library/Preferences/*.plist
///
/// 为什么必须换掉 UserDefaults：偏好 plist 是明文文件，任何本机进程、Time Machine
/// 备份、`plutil -p` 都能直接读出 Open Design 的 session cookie 与 Ollama API Key。
///
/// 属性约定：
/// - `kSecClassGenericPassword` + 固定 service：同一份凭据只有一条记录（account 即存储键）；
/// - `kSecAttrAccessibleAfterFirstUnlock`：菜单栏 App 常驻，登录后即可读，不要求每次解锁；
/// - 不设 `kSecAttrSynchronizable`：凭据不上 iCloud 钥匙串。
public final class KeychainSecretStore: SecretStorage {
    private let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    /// 默认 service（与 App bundle id 保持一致，便于在钥匙串访问里辨认）
    public static let defaultService = "com.example.NetworkMonitor.billing"

    public func secret(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String?, forKey key: String) {
        guard let value, let data = value.data(using: .utf8) else {
            SecItemDelete(baseQuery(forKey: key) as CFDictionary)
            return
        }
        let query = baseQuery(forKey: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { return }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
