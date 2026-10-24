import Foundation

// MARK: - TestRunner 入口
//
// 本文件只保留可执行入口与各测试套件的调度顺序；具体用例位于各 *Tests.swift，
// 断言辅助位于 AssertionHelpers.swift。顶层语句仅允许留在本文件（SPM 可执行入口约束）。

// MARK: - 人工触发的真实索引基准（不参与默认测试流程）
if CommandLine.arguments.contains("--harness-index") {
    runHarnessIndexBenchmark()
    exit(0)
}

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

// MARK: - DSH token 数据层（会话扫描 / 增量索引 / 聚合快照）
runHarnessTokenTests()
runHarnessTokenIndexTests()
runHarnessTokenHourlyTests()

// MARK: - Token tab 展示口径（范围窗口 / 缺省小时 / 环比 / 空态）
runTokenPaneTests()

// MARK: - 截图选区几何（多屏 / Retina / 归一化）
runSnipGeometryTests()

// MARK: - 截图选区交互状态机
runSnipSelectionStateTests()

// MARK: - 窗口检测命中判定
runSnipWindowTests()

// MARK: - 截图文件命名与上次选区编码
runSnipFileTests()

// MARK: - 选区历史（逗号 / 句号循环）
runSnipHistoryTests()

// MARK: - 像素采样与取色格式
runSnipPixelTests()

// MARK: - 尺寸输入与长宽比锁定
runSnipSizeTests()

// MARK: - 标注模型、撤销栈与渲染
runSnipAnnotationTests()

// MARK: - 标注合成导出
runSnipComposerTests()

// MARK: - 马赛克与模糊
runSnipMosaicTests()

// MARK: - 文字标注
runSnipTextTests()

// MARK: - 贴图旋转与镜像
runSnipTransformTests()

// MARK: - 剪贴板内容分类
runSnipClipboardTests()

// MARK: - Done
print("\n🎉 所有测试通过！")