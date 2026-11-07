import Foundation

// MARK: - 计费凭据来源

/// 凭据来源 — 同一 provider 只有一条生效凭据，来源必须是可枚举的其中之一
///
/// 契约（用户反馈「同一个 provider 不支持重复配置」的落地口径）：
/// - 一个 provider id 对应**唯一**一个存储键 `billing.credential.<providerID>`，
///   写入永远是覆盖（不存在「第二份配置」）；
/// - 环境变量（`BILLING_<ID>_API_KEY` / provider 自定义键，如 `OLLAMA_API_KEY`）
///   **只是回退**：只要存储里有值就以存储为准，环境变量不参与、也不会被合并；
/// - 设置页显示的掩码与额度页实际查询用的凭据都取自 `credentialResolution`，
///   两处不可能看到不同来源的「两个配置」。
public enum BillingCredentialSource: String, Sendable, Equatable {
    /// 来自本机偏好存储（用户在设置页填写的）
    case stored
    /// 来自环境变量回退（命令行调试用）
    case environment
    /// 未配置
    case none
}

/// 凭据解析结果 — 生效凭据 + 来源 + 参与解析的键（设置页与日志用）
public struct BillingCredentialResolution: Sendable, Equatable {
    /// 生效凭据（nil = 未配置）
    public let credential: String?
    /// 生效来源
    public let source: BillingCredentialSource
    /// 唯一存储键
    public let storageKey: String
    /// 依次尝试的环境变量键（无命中时也返回，便于排查）
    public let environmentKeys: [String]

    public init(credential: String?, source: BillingCredentialSource,
                storageKey: String, environmentKeys: [String]) {
        self.credential = credential
        self.source = source
        self.storageKey = storageKey
        self.environmentKeys = environmentKeys
    }

    /// 是否已配置（额度页可见性判据的输入）
    public var isConfigured: Bool { credential != nil }
}

// MARK: - 计费凭据存储

/// 计费凭据存储 — 按 provider id 读写 API Key
///
/// 抽成协议的原因：未来可换 Keychain 实现；测试用内存实现，不污染真实偏好。
public protocol BillingCredentialStore: AnyObject, Sendable {
    /// 读取指定 provider 的凭据（无则 nil）
    func credential(for providerID: String) -> String?
    /// 写入凭据（nil 或空串 = 清除）
    func setCredential(_ credential: String?, for providerID: String)
    /// 解析指定 provider 的生效凭据与其来源（同一 provider 只有一条）
    func credentialResolution(for providerID: String) -> BillingCredentialResolution
}

extension BillingCredentialStore {
    /// 默认实现：只能取到生效值，来源按「有值即视为存储」处理
    ///
    /// 真实实现（`PreferencesBillingCredentialStore`）会覆盖本方法并给出精确来源；
    /// 提供默认实现是为了让替换实现（Keychain 等）不必一次性实现全部细节。
    public func credentialResolution(for providerID: String) -> BillingCredentialResolution {
        BillingCredentialResolution(credential: credential(for: providerID),
                                    source: credential(for: providerID) == nil ? .none : .stored,
                                    storageKey: PreferencesBillingCredentialStore.storageKey(for: providerID),
                                    environmentKeys: [])
    }
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
    /// 凭据真正的落点：默认登录钥匙串（偏好存储只保留「迁移前遗留的明文」用于一次性搬迁）
    private let secrets: any SecretStorage
    private let environment: [String: String]
    /// 环境变量键名解析（按 provider 自定义；未注入时用默认规则）
    private let environmentKeyResolver: @Sendable (String) -> String
    /// 日志（迁移这类一次性动作必须可观测）
    private let logger: LoggingService?

    /// 存储键前缀（完整键：`billing.credential.<providerID>`）
    ///
    /// 该键现在只用于两件事：钥匙串里的 account 名，以及搬迁旧明文时的偏好键名。
    public static let keyPrefix = "billing.credential."

    public init(storage: any KeyValueStorage = AppContext.shared.storage,
                secrets: (any SecretStorage)? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                logger: LoggingService? = AppContext.shared.logger,
                environmentKeyResolver: @escaping @Sendable (String) -> String = { providerID in
                    PreferencesBillingCredentialStore.defaultEnvironmentKey(for: providerID)
                }) {
        self.storage = storage
        // 默认走偏好存储（不弹框、不阻塞主线程）；钥匙串需由组合根显式注入，
        // 前提是签名身份稳定 —— 见 PreferencesSecretStore 的说明与实测记录
        self.secrets = secrets ?? PreferencesSecretStore(storage: storage)
        self.environment = environment
        self.logger = logger
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

    /// 生效凭据与其来源 —— 同一 provider 只有一条：存储优先，环境变量仅作回退
    ///
    /// 两者同时存在时**只返回存储里的那条**（不合并、不拼接），设置页掩码与额度页
    /// 实际查询用的是同一个值，从根上排除「一个 provider 两个配置」。
    public func credentialResolution(for providerID: String) -> BillingCredentialResolution {
        let storageKey = Self.storageKey(for: providerID)
        let keys = Self.environmentKeys(for: providerID, resolving: environmentKeyResolver)
        if let stored = storedCredential(for: providerID) {
            return BillingCredentialResolution(credential: stored, source: .stored,
                                               storageKey: storageKey, environmentKeys: keys)
        }
        // 环境变量回退：优先 provider 自定义键（如 Ollama 的 OLLAMA_API_KEY），
        // 再试默认键（连字符转下划线，便于 export），最后兼容旧的带连字符键
        for key in keys {
            if let value = environment[key], !value.isEmpty {
                return BillingCredentialResolution(credential: value, source: .environment,
                                                   storageKey: storageKey, environmentKeys: keys)
            }
        }
        return BillingCredentialResolution(credential: nil, source: .none,
                                           storageKey: storageKey, environmentKeys: keys)
    }

    public func credential(for providerID: String) -> String? {
        if let stored = storedCredential(for: providerID) {
            return stored
        }
        for key in Self.environmentKeys(for: providerID, resolving: environmentKeyResolver) {
            if let value = environment[key], !value.isEmpty { return value }
        }
        return nil
    }

    public func setCredential(_ credential: String?, for providerID: String) {
        let key = Self.storageKey(for: providerID)
        // 迁移遗留：旧版本把明文写在偏好里，写入/清除时都要连带清掉，
        // 否则旧明文会一直留在 plist 里
        storage.removeObject(forKey: key)
        guard let credential, !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            secrets.setSecret(nil, forKey: key)
            return
        }
        secrets.setSecret(credential.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }

    /// 一次性搬迁遗留明文（启动时对全部已注册 provider 调一次）
    ///
    /// 惰性搬迁只在「读该 provider」时触发，用户不点开额度页就一直有明文留在
    /// `~/Library/Preferences` 里。启动时按注册表全量走一遍，代价是每个 provider
    /// 一次钥匙串查询，可忽略。
    public func migrateLegacyPlaintext(for providerIDs: [String]) {
        // 与偏好共用底层时没有「搬迁」这回事，直接跳过（否则会把凭据全删）
        guard !secrets.sharesStorageWithPreferences else { return }
        var moved: [String] = []
        for providerID in providerIDs {
            let key = Self.storageKey(for: providerID)
            let hadPlaintext = storage.string(forKey: key) != nil
            _ = storedCredential(for: providerID)
            if hadPlaintext, storage.string(forKey: key) == nil { moved.append(providerID) }
        }
        // 迁移结果必须可见：否则「明文还在不在」只能靠肉眼翻 plist 才知道
        logger?.info("凭据存储迁移完成：清理明文 \(moved.count) 项\(moved.isEmpty ? "" : "（\(moved.joined(separator: ", "))）")")
    }

    /// 读取生效的存储凭据：钥匙串优先；读到旧版遗留的明文时**就地搬迁**并删除明文
    ///
    /// 搬迁是惰性的：只在用户下次打开额度页 / 设置页读到该 provider 时发生，
    /// 不需要启动时全量扫描，也不会因为某个 provider 从没被访问而一直留明文。
    private func storedCredential(for providerID: String) -> String? {
        let key = Self.storageKey(for: providerID)
        if let secret = secrets.secret(forKey: key),
           !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 只有「秘密存储与偏好是两个地方」时才清理偏好里的旧明文；
            // 共用同一份底层数据时，这里读到的那条就是偏好里那条，清掉等于删凭据
            if !secrets.sharesStorageWithPreferences {
                discardLegacyPlaintext(for: providerID)
            }
            return secret
        }
        guard let legacy = storage.string(forKey: key),
              !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        secrets.setSecret(trimmed, forKey: key)
        storage.removeObject(forKey: key)
        return trimmed
    }

    /// 清掉偏好里可能残留的旧明文（幂等；非空时才调用 `removeObject`）
    private func discardLegacyPlaintext(for providerID: String) {
        let key = Self.storageKey(for: providerID)
        guard storage.string(forKey: key) != nil else { return }
        storage.removeObject(forKey: key)
    }
}
