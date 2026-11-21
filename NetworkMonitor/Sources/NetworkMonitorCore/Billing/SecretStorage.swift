// MARK: - 秘密存储协议

/// 秘密存储 — 凭据这类「可直接冒用」的内容一律走这里，不走键值偏好
///
/// 抽成协议的原因：单测不能往真实 Keychain 里写垃圾（会污染本机钥匙串，
/// 也让测试互相干扰），测试注入内存实现即可。
///
/// 现有实现：`EncryptedSecretStore`（默认，AES-GCM 密文落在偏好存储里）；
/// 测试替身 `InMemorySecretStorage`。
public protocol SecretStorage: AnyObject, Sendable {
    /// 是否与偏好存储共用同一份底层数据
    ///
    /// 搬迁旧明文的前提是「秘密存储与偏好存储是两个地方」；共用时（如 `EncryptedSecretStore`
    /// 把密文写回偏好），读到的「秘密」就是偏好里那条，再按搬迁逻辑删明文等于**把凭据删掉**。
    ///
    /// 必须是协议要求而不是扩展默认实现：实测扩展里的默认值**不进 witness table**，
    /// 通过 `any SecretStorage` 调用会静态解析到默认 false，共用底层时照样走搬迁分支。
    var sharesStorageWithPreferences: Bool { get }
    /// 读取（无则 nil）
    func secret(forKey key: String) -> String?
    /// 写入（nil = 删除）
    func setSecret(_ value: String?, forKey key: String)
}
