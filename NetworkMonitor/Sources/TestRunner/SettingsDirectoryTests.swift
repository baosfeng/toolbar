import Foundation
import NetworkMonitorCore

// MARK: - 目录偏好测试

/// 截图快速保存目录 / 互传接收目录的自定义偏好 — 默认、写入、清除与解析
///
/// 只用内存存储（`InMemoryStorage`），不污染真实 UserDefaults。
func runSettingsDirectoryTests() {
    print("\n🧪 Testing 目录偏好...")

    let home = URL(fileURLWithPath: "/Users/tester")
    let storage = InMemoryStorage()

    // 截图：默认目录
    let defaultSnip = SnipFileNaming.quickSaveDirectory(homeDirectory: home)
    assertEqual(SnipSaveDirectory.customPath(storage: storage) == nil, true, "默认没有自定义路径")
    assertEqual(SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage,
                                                            homeDirectory: home).path,
                defaultSnip.path, "未自定义时回落到默认目录")

    // 截图：自定义后生效，且路径被标准化
    let custom = URL(fileURLWithPath: "/Users/tester/Desktop/截图")
    SnipSaveDirectory.setCustomDirectory(custom, storage: storage)
    assertEqual(SnipSaveDirectory.customPath(storage: storage), custom.standardizedFileURL.path,
                "自定义路径按标准形式落盘")
    assertEqual(SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage,
                                                            homeDirectory: home).path,
                custom.standardizedFileURL.path, "自定义优先于默认")

    // 截图：空白值视为未设置
    storage.set("   ", forKey: SnipSaveDirectory.key)
    assertEqual(SnipSaveDirectory.customPath(storage: storage) == nil, true, "空白值不算自定义")

    // 截图：清除后回默认
    SnipSaveDirectory.setCustomDirectory(nil, storage: storage)
    assertEqual(SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage,
                                                            homeDirectory: home).path,
                defaultSnip.path, "清除自定义后回默认")

    // 互传：往返与解析
    let transferStorage = InMemoryStorage()
    let preferences = TransferPreferences(storage: transferStorage)
    let fallback = URL(fileURLWithPath: "/Users/tester/Downloads/局域网互传")
    assertEqual(preferences.receiveDirectoryPath == nil, true, "默认没有自定义接收目录")
    assertEqual(preferences.resolvedReceiveDirectory(fallback: fallback).path, fallback.path,
                "未自定义时回落到传入默认目录")

    let receiveDir = URL(fileURLWithPath: "/Users/tester/Downloads/收件")
    preferences.receiveDirectoryPath = receiveDir.path
    assertEqual(preferences.receiveDirectoryPath, receiveDir.path, "接收目录写入后可读回")
    assertEqual(preferences.resolvedReceiveDirectory(fallback: fallback).path, receiveDir.path,
                "自定义接收目录优先")

    preferences.receiveDirectoryPath = "  "
    assertEqual(preferences.receiveDirectoryPath == nil, true, "空白接收目录视为清除")

    // 互传：线程安全容器
    let store = ReceiveDirectoryStore(fallback)
    assertEqual(store.current.path, fallback.path, "容器初始值")
    store.update(receiveDir)
    assertEqual(store.current.path, receiveDir.path, "容器更新后立即可读")

    print("✅ 目录偏好 works")
}
