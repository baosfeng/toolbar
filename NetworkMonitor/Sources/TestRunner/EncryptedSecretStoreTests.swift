import CryptoKit
import Foundation
import NetworkMonitorCore

// MARK: - 本地加密存储

/// 凭据必须以密文落盘，且能原样读回；换机器/丢密钥文件时降级为「未配置」而不是崩
func runEncryptedSecretStoreTests() {
    print("🧪 Testing 本地加密凭据存储...")

    let storage = InMemoryStorage()
    let material = LocalKeyMaterial(machineSeed: Data("machine-A".utf8),
                                    fileSeed: Data(repeating: 0x5A, count: 32))
    let store = EncryptedSecretStore(storage: storage, keyMaterial: material, logger: nil)
    let key = "billing.credential.ollama"

    // 1) 写入后落盘的是密文，且带版本前缀
    store.setSecret("sk-live-1234567890", forKey: key)
    let raw = storage.string(forKey: key) ?? ""
    assertEqual(raw.hasPrefix(EncryptedSecretStore.ciphertextPrefix), true, "落盘内容带 enc:v1 前缀")
    assertEqual(raw.contains("sk-live"), false, "落盘内容不含明文")
    assertEqual(raw.count > EncryptedSecretStore.ciphertextPrefix.count, true, "密文非空")

    // 2) 读回原值
    assertEqual(store.secret(forKey: key), "sk-live-1234567890", "能原样读回")

    // 3) 历史明文：读到时就地加密，值不变
    let legacyStorage = InMemoryStorage()
    legacyStorage.set("sk-legacy-plain", forKey: key)
    let legacyStore = EncryptedSecretStore(storage: legacyStorage, keyMaterial: material, logger: nil)
    assertEqual(legacyStore.secret(forKey: key), "sk-legacy-plain", "历史明文读取值不变")
    let migrated = legacyStorage.string(forKey: key) ?? ""
    assertEqual(migrated.hasPrefix(EncryptedSecretStore.ciphertextPrefix), true, "历史明文被就地加密")
    assertEqual(migrated.contains("sk-legacy-plain"), false, "加密后不含明文")
    assertEqual(legacyStore.secret(forKey: key), "sk-legacy-plain", "加密回写后仍读得回")

    // 4) 清除
    store.setSecret(nil, forKey: key)
    assertEqual(storage.string(forKey: key) == nil, true, "nil 删除密文")
    assertEqual(store.secret(forKey: key) == nil, true, "删除后读不到")

    // 5) 密钥材料变了（换机器 / 密钥文件丢）：返回 nil，不崩、不返回半截值
    let otherMaterial = LocalKeyMaterial(machineSeed: Data("machine-B".utf8),
                                         fileSeed: Data(repeating: 0x11, count: 32))
    let crossStore = EncryptedSecretStore(storage: storage, keyMaterial: otherMaterial, logger: nil)
    let sealedStorage = InMemoryStorage()
    EncryptedSecretStore(storage: sealedStorage, keyMaterial: material, logger: nil)
        .setSecret("sk-bound", forKey: key)
    assertEqual(crossStore.secret(forKey: key) == nil, true, "密钥材料不符时按未配置处理")
    assertEqual(EncryptedSecretStore(storage: sealedStorage, keyMaterial: material, logger: nil)
        .secret(forKey: key), "sk-bound", "同一材料仍可解")

    // 6) 与偏好共用底层：不得触发「搬迁并删明文」那条分支
    assertEqual(store.sharesStorageWithPreferences, true, "加密存储与偏好共用底层")

    print("✅ 本地加密凭据存储 works")
}

/// 密钥材料：机器绑定 + 密钥文件分离
func runLocalKeyMaterialTests() {
    print("🧪 Testing 本地密钥材料...")

    let a = LocalKeyMaterial(machineSeed: Data("m".utf8), fileSeed: Data(repeating: 1, count: 32))
    let b = LocalKeyMaterial(machineSeed: Data("m".utf8), fileSeed: Data(repeating: 2, count: 32))
    let c = LocalKeyMaterial(machineSeed: Data("n".utf8), fileSeed: Data(repeating: 1, count: 32))

    // 两段材料缺一不可：任一不同，派生的密钥就不同
    func seal(_ material: LocalKeyMaterial) -> Data {
        let key = material.deriveKey()
        let box = try! AES.GCM.seal(Data("payload".utf8), using: key)
        return box.combined!
    }
    func canOpen(_ combined: Data, with material: LocalKeyMaterial) -> Bool {
        (try? AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: material.deriveKey())) != nil
    }
    let sealedByA = seal(a)
    assertEqual(canOpen(sealedByA, with: a), true, "同材料可解")
    assertEqual(canOpen(sealedByA, with: b), false, "仅密钥文件不同则解不开")
    assertEqual(canOpen(sealedByA, with: c), false, "仅机器不同则解不开")

    // 机器 UUID 能取到，且是稳定的（同一台机器两次调用相同）
    let uuid1 = LocalKeyMaterial.machineUUID()
    let uuid2 = LocalKeyMaterial.machineUUID()
    assertEqual(uuid1.count, 16, "机器 UUID 为 16 字节")
    assertEqual(uuid1 == uuid2, true, "同一机器 UUID 稳定")

    // 密钥文件路径与偏好 plist 分离存放
    assertEqual(LocalKeyMaterial.keyFilePath.contains("Application Support"), true,
                "密钥文件在 Application Support 下")
    assertEqual(LocalKeyMaterial.keyFilePath.contains("credentials.key"), true,
                "密钥文件名固定")

    print("✅ 本地密钥材料 works")
}
