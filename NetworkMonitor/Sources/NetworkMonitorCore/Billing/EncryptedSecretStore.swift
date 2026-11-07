import CryptoKit
import Foundation
import Security

// MARK: - 本地加密的秘密存储

/// 本地加密的秘密存储 — 凭据只存在本机，且以 AES-GCM 密文落盘
///
/// 与钥匙串的区别：**不依赖代码签名身份**，因此自签名 / ad-hoc 构建不会弹
/// 「想要使用钥匙串中的机密信息」授权框（那种弹框会阻塞主线程把菜单栏 App 卡死，
/// 见 `docs/踩坑/运行时/自签名App读钥匙串卡死.md`）。
///
/// 密钥材料（两段拼接后 HKDF 派生，缺一不可）：
/// 1. 本机硬件 UUID（`gethostuuid`）—— 换机器后密文即失效，不随备份跨机还原；
/// 2. 本机随机密钥文件 `~/Library/Application Support/macMonitor/credentials.key`
///    （权限 0600，首次使用时生成）—— 与偏好 plist 分开放，
///    单独拷走 plist 或 Time Machine 只还原 plist 都解不开。
///
/// **能力边界（必须知道）**：这挡的是「明文外泄」——随手 `plutil -p`、
/// 备份/同步被带走、误发文件、日志与截图里出现完整 key。它**挡不住**
/// 以同一用户身份运行的恶意进程（它既能读 plist 也能读密钥文件）。
/// 要防这一层只能用钥匙串或用户口令，前者要求稳定签名身份，后者要求每次输入。
///
/// 密文格式：`enc:v1:` + base64(AES-GCM combined，含 nonce 与 tag)。
/// 没有该前缀的旧值视为历史明文，读取时就地加密回写（不是删除，值不变）。
public final class EncryptedSecretStore: SecretStorage {

    /// 密文前缀（带版本号，便于以后换算法/换密钥材料时平滑迁移）
    public static let ciphertextPrefix = "enc:v1:"

    private let storage: any KeyValueStorage
    /// 派生密钥（不叫 key，避免与各方法里的 storageKey 参数名遮蔽，曾因此编译失败）
    private let derivedKey: SymmetricKey
    private let logger: LoggingService?

    /// 与偏好共用同一份底层数据：不需要「搬到别处并删明文」，
    /// 历史明文在读取时就地加密（值不变），因此不能走删旧值那条分支
    public var sharesStorageWithPreferences: Bool { true }

    public init(storage: any KeyValueStorage = AppContext.shared.storage,
                keyMaterial: LocalKeyMaterial = .machineBound(),
                logger: LoggingService? = AppContext.shared.logger) {
        self.storage = storage
        self.derivedKey = keyMaterial.deriveKey()
        self.logger = logger
    }

    public func secret(forKey key: String) -> String? {
        guard let raw = storage.string(forKey: key), !raw.isEmpty else { return nil }
        guard raw.hasPrefix(Self.ciphertextPrefix) else {
            // 历史明文：就地加密回写，调用方拿到的仍是原值
            encryptInPlace(raw, forKey: key)
            return raw
        }
        let encoded = raw.dropFirst(Self.ciphertextPrefix.count)
        guard let combined = Data(base64Encoded: String(encoded)),
              let opened = try? AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: self.derivedKey),
              let text = String(data: opened, encoding: .utf8) else {
            // 解不开：换机器 / 密钥文件丢失 / 密文损坏。不崩、不返回半截值，
            // 让上层按「未配置」处理，用户重填一次即可
            logger?.warning("凭据解密失败（密钥材料可能已变），请重新填写")
            return nil
        }
        return text
    }

    public func setSecret(_ value: String?, forKey key: String) {
        guard let value, !value.isEmpty else {
            storage.removeObject(forKey: key)
            return
        }
        storage.set(Self.encrypt(value, using: self.derivedKey), forKey: key)
    }

    /// 把历史明文就地加密（值本身不变，读一次仍是同一个 key）
    private func encryptInPlace(_ plaintext: String, forKey key: String) {
        storage.set(Self.encrypt(plaintext, using: self.derivedKey), forKey: key)
    }

    static func encrypt(_ plaintext: String, using key: SymmetricKey) -> String {
        guard let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: key),
              let combined = sealed.combined else {
            // 加密失败宁可写空也不写明文：写明文等于把「加密存储」这层保证作废
            return ciphertextPrefix
        }
        return ciphertextPrefix + combined.base64EncodedString()
    }
}

// MARK: - 密钥材料

/// 本地密钥材料 — 机器 UUID + 随机密钥文件，HKDF-SHA256 派生出 AES-256 密钥
public struct LocalKeyMaterial: Sendable {
    /// 机器标识（无法取得时为固定占位，此时只剩密钥文件一层保护）
    public let machineSeed: Data
    /// 随机密钥文件内容（32 字节）
    public let fileSeed: Data

    public init(machineSeed: Data, fileSeed: Data) {
        self.machineSeed = machineSeed
        self.fileSeed = fileSeed
    }

    /// 派生 AES-256 密钥（HKDF 把两段材料与用途标签绑定，换用途不会撞钥匙）
    public func deriveKey() -> SymmetricKey {
        let input = SymmetricKey(data: machineSeed + fileSeed)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: input,
                                      salt: Data("com.example.NetworkMonitor.credentials".utf8),
                                      info: Data("billing-credential-v1".utf8),
                                      outputByteCount: 32)
    }

    /// 本机默认材料：硬件 UUID + Application Support 下的 0600 随机密钥文件
    ///
    /// 密钥文件首次使用时生成；生成失败（磁盘只读等）退化为「只有机器 UUID」，
    /// 仍然加密，只是少一层与 plist 分离的保护。
    public static func machineBound() -> LocalKeyMaterial {
        LocalKeyMaterial(machineSeed: machineUUID(),
                         fileSeed: loadOrCreateKeyFile() ?? Data())
    }

    /// 硬件 UUID（`gethostuuid`）；失败时返回空 Data
    public static func machineUUID() -> Data {
        var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        guard gethostuuid(&uuid, &timeout) == 0 else { return Data() }
        return withUnsafeBytes(of: uuid) { Data($0) }
    }

    /// 密钥文件路径（与偏好 plist 分离存放）
    public static var keyFilePath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("macMonitor", isDirectory: true)
            .appendingPathComponent("credentials.key").path
    }

    /// 读取密钥文件；不存在则生成 32 字节随机内容并以 0600 写入
    static func loadOrCreateKeyFile() -> Data? {
        let path = keyFilePath
        if let data = FileManager.default.contents(atPath: path), data.count >= 32 {
            return data
        }
        var seed = Data(count: 32)
        let generated = seed.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard generated == 0 else { return nil }

        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // 文件属性直接以 0600 落盘，避免「先按默认权限建再改」的窗口期
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard FileManager.default.createFile(atPath: path, contents: seed, attributes: attributes) else {
            return nil
        }
        return seed
    }
}
