import Foundation

// MARK: - 套件登记：Clipboard 域
//
// 覆盖：仓储 / 搜索 / 卡片 / 图片 / 清理
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
func runClipboardSuites() {
    runClipboardAccessTests()
    runClipboardHashTests()
    runClipboardFuzzySearchTests()
    // 事务原语 / 迁移登记表 / 删板原子性（一个业务动作 = 一个事务）
    runDatabaseTransactionTests()
    runMigrationRegistryTests()
    runBoardDeleteAtomicityTests()
    runClipboardSchemaLadderTests()  // schema 阶梯（迁移幂等 / 列序不错位）先行：后续仓储断言依赖表结构已就位
    runClipboardRepositoryTests()
    runClipboardBoardTests()  // 板仓储（建 / 改名 / 移动 / 删板连带删条目 / 双重豁免）
    runClipboardFullTextSearchTests()
    runClipboardLimitsTests()
    runClipboardUninitializedTests()
    runClipboardBindingLifetimeTests()
    runClipboardEditingTests()  // 编辑 / 手动新建（哈希重算、冲突合并、空内容拒绝、无来源）
    runClipboardPanelMockTests()
    runClipboardRelativeTimeTests()
    runClipboardImagePolicyTests()
    runClipboardImageCandidateSelectionTests()  // 采集候选选择：超限不再静默丢弃（改占位）
    runClipboardImageStoreTests()
    runClipboardCardWindowTests()  // 卡片流滑动窗口（内存削减口径）
    runClipboardSelectionTests()  // 卡片多选变换（单击 / ⌘ / ⇧ / ⌘A / 清空）
    runClipboardDragPayloadTests()  // 卡片拖拽到其他 App 的载荷构造（阈值 / 文本 / 图片 / 文件 / 多选）
    runClipboardBatchDeleteTests()  // 多选批量删除的存储口径（命中 / 忽略缺失 / 空集合 / 幂等）
    runClipboardImageGCTests()
    runClipboardCapacityTests()
    runClipboardTextClassifierTests()
    runClipboardFileClassifierTests()
    runClipboardFileSummaryTests()
    runClipboardStorageUsageTests()
    runClipboardImageFormatTests()
    runSnipClipboardTests()
    runClipboardPollScheduleTests()
    runClipboardPauseTests()
    runClipboardCardGeometryTests()
    runClipboardDetailStripTests()
    runClipboardFilterTokenTests()
    runClipboardSearchHighlightTests()
    runClipboardToolbarLayoutTests()  // 工具条横向分配（芯片行不溢出 / 搜索框不被压到下限以下）
    runClipboardBoardRowTests()  // 板标签行（不溢出 / ＋恒在）+ 切板过滤 + ⌘←/→ 环回
    runClipboardThumbnailGateTests()
    runClipboardThumbnailRetryPolicyTests()
    runClipboardThumbnailDecodeTests()
    runClipboardDeleteConfirmTests()
    runClipboardOCRTests()
    runClipboardPreviewTests()
    runClipboardHeadBandContrastTests()
    runClipboardFooterTextTests()
}
