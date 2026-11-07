import Foundation
import NetworkMonitorCore

// MARK: - 凭据存储：默认实现不得删除既有凭据

/// 默认（偏好）秘密存储下，迁移与读取都不能把已有凭据删掉
///
/// 背景：钥匙串方案在自签名 App 上会弹 ACL 授权框并阻塞主线程（实测启动即卡死），
/// 默认改回偏好存储后，搬迁逻辑若不加守卫会把「读到的那条」当成「遗留明文」删掉，
/// 等于把用户凭据清空。这里锁住这条不变量。
func runCredentialStorageSafetyTests() {
    print("🧪 Testing 凭据存储默认实现安全性...")

    let storage = InMemoryStorage()
    let store = PreferencesBillingCredentialStore(storage: storage, environment: [:])
    let key = PreferencesBillingCredentialStore.storageKey(for: "ollama")

    // 默认实现：加密后与偏好共用底层，标记必须为 true（决定搬迁是否跳过）
    store.setCredential("sk-keep-me", for: "ollama")
    assertEqual(store.credential(for: "ollama"), "sk-keep-me", "写入后可读")
    let persisted = storage.string(forKey: key) ?? ""
    assertEqual(persisted.hasPrefix(EncryptedSecretStore.ciphertextPrefix), true,
                "默认实现写入的是密文")
    assertEqual(persisted.contains("sk-keep-me"), false, "偏好里不留明文")

    // 多次读取不得删除（读路径曾把「读到的秘密」当遗留明文清掉）
    for _ in 0..<3 {
        assertEqual(store.credential(for: "ollama"), "sk-keep-me", "重复读取不丢凭据")
        assertEqual(store.credentialResolution(for: "ollama").credential, "sk-keep-me",
                    "解析结果同样不丢")
    }
    assertEqual(storage.string(forKey: key) == persisted, true, "重复读取后密文不变")

    // 迁移入口在共用底层时必须无副作用
    store.migrateLegacyPlaintext(for: ["ollama", "open-design"])
    assertEqual(store.credential(for: "ollama"), "sk-keep-me", "调用迁移不影响既有凭据")

    // 清除语义仍然有效
    store.setCredential(nil, for: "ollama")
    assertEqual(store.credential(for: "ollama") == nil, true, "nil 清除凭据")
    assertEqual(storage.string(forKey: key) == nil, true, "清除后存储里也不留")

    print("✅ 凭据存储默认实现安全性 works")
}

/// 独立秘密存储（钥匙串形态）下，旧明文才应被搬迁并删除
func runCredentialMigrationTests() {
    print("🧪 Testing 凭据明文搬迁...")

    let storage = InMemoryStorage()
    let secrets = InMemorySecretStorage()
    let key = PreferencesBillingCredentialStore.storageKey(for: "ollama")
    // 模拟旧版本：明文只在偏好里
    storage.set("sk-legacy", forKey: key)

    let store = PreferencesBillingCredentialStore(storage: storage, secrets: secrets, environment: [:])
    store.migrateLegacyPlaintext(for: ["ollama"])

    assertEqual(secrets.secret(forKey: key), "sk-legacy", "明文被搬进秘密存储")
    assertEqual(storage.string(forKey: key) == nil, true, "偏好里的明文被删除")
    assertEqual(store.credential(for: "ollama"), "sk-legacy", "搬迁后凭据仍可用")

    print("✅ 凭据明文搬迁 works")
}
