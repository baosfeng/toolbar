import Foundation
import Security

// MARK: - 秘密存储协议

/// 秘密存储 — 凭据这类「可直接冒用」的内容一律走这里，不走键值偏好
///
/// 抽成协议的原因：单测不能往真实 Keychain 里写垃圾（会污染本机钥匙串，
/// 也让测试互相干扰），测试注入内存实现即可。
public protocol SecretStorage: AnyObject, Sendable {
    /// 是否与偏好存储共用同一份底层数据
    ///
    /// 搬迁旧明文的前提是「秘密存储与偏好存储是两个地方」；共用时（`PreferencesSecretStore`）
    /// 读到的「秘密」就是偏好里那条，再按搬迁逻辑删明文等于**把凭据删掉**。
    ///
    /// 必须是协议要求而不是扩展默认实现：实测扩展里的默认值**不进 witness table**，
    /// 通过 `any SecretStorage` 调用会静态解析到默认 false，共用底层时照样走搬迁分支。
    var sharesStorageWithPreferences: Bool { get }
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

    /// 钥匙串与偏好是两个独立存储：旧明文可以安全搬迁
    public var sharesStorageWithPreferences: Bool { false }

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
// MARK: - 偏好存储实现（默认，不弹框）

/// 偏好存储实现 — 把「秘密」写回 `KeyValueStorage`，行为与启用钥匙串前一致
///
/// **为什么默认不用钥匙串**（实测）：本项目用自签名证书（`NetworkMonitor Local Signing`）
/// 或 ad-hoc 回落，**每次重建签名身份都会变**，而钥匙串 ACL 是按代码签名绑定的。
/// 身份一变，`SecItemCopyMatching` 就会弹「NetworkMonitor 想要使用钥匙串中的机密信息」
/// 并**阻塞调用线程**——实测菜单栏 App 启动即卡死在这个弹框上（`sample` 显示主线程停在
/// `SecItemCopyMatching`）。在签名身份稳定（正式证书 / 公证分发）之前，钥匙串不能做默认。
///
/// 启用前提：配置稳定签名证书并确认 `codesign -d -r-` 的 designated requirement
/// 不含 cdhash（`build-app.sh` 的 `assert_stable_signature` 会拦这一条），
/// 再把组合根换成 `KeychainSecretStore`。
public final class PreferencesSecretStore: SecretStorage {
    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage) {
        self.storage = storage
    }

    /// 与偏好共用同一份底层数据：读取时不能再按「搬迁明文」处理
    public var sharesStorageWithPreferences: Bool { true }

    public func secret(forKey key: String) -> String? { storage.string(forKey: key) }

    public func setSecret(_ value: String?, forKey key: String) {
        if let value {
            storage.set(value, forKey: key)
        } else {
            storage.removeObject(forKey: key)
        }
    }
}
