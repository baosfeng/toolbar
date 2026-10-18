import Foundation

// MARK: - 计费凭据存储

/// 计费凭据存储 — 按 provider id 读写 API Key
///
/// 抽成协议的原因：未来可换 Keychain 实现；测试用内存实现，不污染真实偏好。
public protocol BillingCredentialStore: AnyObject, Sendable {
    /// 读取指定 provider 的凭据（无则 nil）
    func credential(for providerID: String) -> String?
    /// 写入凭据（nil 或空串 = 清除）
    func setCredential(_ credential: String?, for providerID: String)
}

// MARK: - 默认实现（偏好存储 + 环境变量回退）

/// 偏好存储实现 — API Key 存 `KeyValueStorage`，并支持环境变量只读回退
///
/// 环境变量回退用于命令行调试（`BILLING_OLLAMA_API_KEY=xxx ./NetworkMonitor`）；
/// LaunchServices 启动的 .app 拿不到 shell 环境变量，因此仅作补充。
public final class PreferencesBillingCredentialStore: BillingCredentialStore {
    private let storage: any KeyValueStorage
    private let environment: [String: String]

    /// 存储键前缀（完整键：`billing.credential.<providerID>`）
    public static let keyPrefix = "billing.credential."

    public init(storage: any KeyValueStorage = AppContext.shared.storage,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.storage = storage
        self.environment = environment
    }

    /// 指定 provider 的偏好存储键
    public static func storageKey(for providerID: String) -> String {
        keyPrefix + providerID
    }

    public func credential(for providerID: String) -> String? {
        if let stored = storage.string(forKey: Self.storageKey(for: providerID)),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        // 环境变量回退：BILLING_<ID>_API_KEY
        let envKey = "BILLING_\(providerID.uppercased())_API_KEY"
        guard let value = environment[envKey], !value.isEmpty else { return nil }
        return value
    }

    public func setCredential(_ credential: String?, for providerID: String) {
        let key = Self.storageKey(for: providerID)
        guard let credential, !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            storage.removeObject(forKey: key)
            return
        }
        storage.set(credential.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }
}
