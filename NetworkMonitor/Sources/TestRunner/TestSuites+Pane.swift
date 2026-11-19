import Foundation

// MARK: - 套件登记：Pane 域
//
// 覆盖：分页装配 / 自绘层 / 主题 / 面板高度
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
func runPaneSuites() {
    runSettingsDirectoryTests()
    runMenuPanelMetricsTests()
    runPaneValueFormattingTests()
    runPaneCardLayoutTests()
    runPaneValueSizingTests()
    runMenuBarDisplayTests()
    runSettingsOrderTests()
    runPaneHeightBudgetTests()
    runPaneAssemblyTests()
    runDrawnRowLayoutTests()
    runDrawnInteractionTests()
    runDrawnUnflipTests()
    runDrawnSurfaceMathTests()
    runPanelTabCatalogTests()  // 分页
    runThemeContrastTests()
    runRenderTierTests()
    runRenderTierGlassTests()
    runRenderTierGateTests()
    runAppearancePreferencesTests()
    runSettingsThemeTests()
}
