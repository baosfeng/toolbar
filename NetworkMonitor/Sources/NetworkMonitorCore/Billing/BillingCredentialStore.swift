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
///
/// 键名解析：provider 可以自定义（Ollama 的 `OLLAMA_API_KEY`），未自定义时用
/// `BILLING_<ID 大写，连字符转下划线>_API_KEY`（`opencode-go` → `BILLING_OPENCODE_GO_API_KEY`），
/// 这样形如 `opencode-go` 的复合 id 也能被 shell `export`。
public final class PreferencesBillingCredentialStore: BillingCredentialStore {
    private let storage: any KeyValueStorage
    private let environment: [String: String]
    /// 环境变量键名解析（按 provider 自定义；未注入时用默认规则）
    private let environmentKeyResolver: @Sendable (String) -> String

    /// 存储键前缀（完整键：`billing.credential.<providerID>`）
    public static let keyPrefix = "billing.credential."

    public init(storage: any KeyValueStorage = AppContext.shared.storage,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                environmentKeyResolver: @escaping @Sendable (String) -> String = { providerID in
                    PreferencesBillingCredentialStore.defaultEnvironmentKey(for: providerID)
                }) {
        self.storage = storage
        self.environment = environment
        self.environmentKeyResolver = environmentKeyResolver
    }

    /// 指定 provider 的偏好存储键
    public static func storageKey(for providerID: String) -> String {
        keyPrefix + providerID
    }

    /// 默认环境变量键名：连字符转下划线，保证可 export
    public static func defaultEnvironmentKey(for providerID: String) -> String {
        "BILLING_\(providerID.uppercased().replacingOccurrences(of: "-", with: "_"))_API_KEY"
    }

    /// 旧的带连字符键名（`opencode-go` → `BILLING_OPENCODE-GO_API_KEY`）
    ///
    /// 仅作兼容：连字符键无法在 shell 里 `export`，保留它免得已固化的调试脚本失效。
    public static func legacyEnvironmentKey(for providerID: String) -> String {
        "BILLING_\(providerID.uppercased())_API_KEY"
    }

    /// 依次尝试的键：自定义 → 默认 → 旧键（去重）
    static func environmentKeys(for providerID: String,
                                resolving resolver: (String) -> String) -> [String] {
        var keys = [resolver(providerID), defaultEnvironmentKey(for: providerID),
                    legacyEnvironmentKey(for: providerID)]
        if let first = keys.first {
            keys = keys.filter { $0 != first }
            keys.insert(first, at: 0)
        }
        return keys
    }

    public func credential(for providerID: String) -> String? {
        if let stored = storage.string(forKey: Self.storageKey(for: providerID)),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        // 环境变量回退：优先 provider 自定义键（如 Ollama 的 OLLAMA_API_KEY），
        // 再试默认键（连字符转下划线，便于 export），最后兼容旧的带连字符键
        for key in Self.environmentKeys(for: providerID, resolving: environmentKeyResolver) {
            if let value = environment[key], !value.isEmpty { return value }
        }
        return nil
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
