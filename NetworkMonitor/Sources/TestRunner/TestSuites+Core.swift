import Foundation

// MARK: - 套件登记：Core 域
//
// 覆盖：格式化 / 配置 / 事件总线 / 通知 / 凭据 / 数据库队列 / 版本与偏好迁移
//
// 本域全部测试入口的**唯一登记处**：新增本域测试文件时只在这里加一行调用，
// 不必改 main.swift（它只剩域调度、不再随测试增长，不会贴到 500 行门禁线）。
// 顺序即执行顺序；行尾注释是该套件覆盖的口径。忘了登记不会编译报错，
// 但 TestSuiteRegistrationTests 会把「定义了却没人调用」的套件判红。
//
// @MainActor 与改造前的顶层代码保持同等隔离语义：原先 main.swift 的顶层语句
// 在 Swift 6 下就是 MainActor，个别套件（runClipboardPanelMockTests）本身是
// @MainActor，域函数不标就会报 actor 隔离错误。

@MainActor
func runCoreSuites() {
    runCoreFormattingTests()
    runTrafficTrackerTests()
    runDatabaseConfigTests()
    runAppEventsTests()
    runLogRedactionTests()
    runHTTPTransportTests()
    runNotificationTests()
    runCueSoundSynthTests()
    runCueSoundStoreTests()
    runCueSoundMigrationTests()
    runEncryptedSecretStoreTests()
    runLocalKeyMaterialTests()
    runCredentialStorageSafetyTests()
    runCredentialMigrationTests()
    runNumberUnitTests()
    runSourceAppPaletteTests()
    runUpdateVersionTests()
    runUpdateCheckStateTests()
    runUpdateCheckerTests()
    runDatabaseReadQueueTests()
    runDatabaseQueueWaitTests()
    runLatestRequestGateTests()
    runSnapshotClockTests()
    runPreferenceDomainMigrationTests()
    runAppAssemblyTests()  // 启动装配：拓扑排序 / 缺依赖 / 成环 / 与改造前手写顺序等价
    // MARK: - 套件登记守卫（守护本文件本身：孤儿测试文件静默不跑）
    runTestSuiteRegistrationTests()
}
