import Foundation

// MARK: - 套件登记：Token 域
//
// 覆盖：DSH 事件流索引 / 派生口径 / 四屏契约
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
func runTokenSuites() {
    runTokenTimeZoneNoteTests()
    runHarnessTokenTests()
    runHarnessStreamMemoryTests()
    runHarnessTokenIndexTests()
    runHarnessTokenHourlyTests()
    runHarnessStreamMemoryRegressionTests()
    runHarnessFollowupTests()
    runHarnessDegradationTests()
    runTokenPaneTests()
    runTokenDeriveTests()
    runTokenPresentationTests()
    runTokenRangeConsistencyTests()
    runTokenHoverTipTests()
    runTokenScreenTests()
    runTokenDistroTotalsTests()
    runThemeTokenTests()
    runHarnessAggregateThrottleTests()
    // 多来源：解析器（Claude / Codex）、来源收窄与单源视图、token.* 偏好键
    runTokenSourceClaudeParserTests()
    runTokenSourceCodexParserTests()
    runTokenSourceParsingBridgeTests()
    runTokenSourceScopeTests()
    runTokenSourcePreferenceTests()
    // 自动监控时间口径（Core）与来源状态四档文案（UI）—— 已下沉的纯口径
    runTokenAutoIndexScheduleTests()
    runTokenSourceStatusTextTests()
}
