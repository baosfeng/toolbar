import Foundation

// MARK: - TestRunner 入口
//
// 本文件只保留可执行入口与各测试套件的调度顺序；具体用例位于各 *Tests.swift，
// 断言辅助位于 AssertionHelpers.swift。顶层语句仅允许留在本文件（SPM 可执行入口约束）。

// MARK: - Core 纯函数：格式化与解析
runCoreFormattingTests()

// MARK: - 每日流量追踪
runTrafficTrackerTests()

// MARK: - 时区与货币配置
runDatabaseConfigTests()

// MARK: - AppEvents 事件总线
runAppEventsTests()

// MARK: - 剪贴板：哈希 / 忽略判定 / 模糊搜索
runClipboardHashTests()
runClipboardFuzzySearchTests()

// MARK: - 剪贴板：仓储 / 全文检索 / 超限清理 / 未初始化容错
runClipboardRepositoryTests()
runClipboardFullTextSearchTests()
runClipboardLimitsTests()
runClipboardUninitializedTests()

// MARK: - 剪贴板：面板数据流与相对时间
runClipboardPanelMockTests()
runClipboardRelativeTimeTests()

// MARK: - 菜单面板取数口径
runMenuPanelMetricsTests()

// MARK: - 局域网文件互传
runTransferTests()

// MARK: - 扫码接收（二维码 + 浏览器直传）
runScanTests()

// MARK: - 计费额度（provider 抽象 + Ollama 响应解码）
runBillingTests()

// MARK: - 额度阈值提醒（5%/4%/3%/2%/1%）
runBillingAlertTests()

// MARK: - Open Design 额度（归一化 / 工作区发现 / 窗口映射 / 用量聚合）
runOpenDesignBillingTests()

// MARK: - Done
print("\n🎉 所有测试通过！")
