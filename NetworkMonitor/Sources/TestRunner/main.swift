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

// MARK: - 人工触发的真实网络自证（不参与默认测试流程）
if CommandLine.arguments.contains("--update-check-live") {
    runUpdateCheckLiveProbe()
    exit(0)
}

// MARK: - 人工触发的单位对照表（改前 → 改后，不参与默认测试流程）
if CommandLine.arguments.contains("--number-unit-table") {
    runNumberUnitTable()
    exit(0)
}

// MARK: - Core 纯函数：格式化与解析
runCoreFormattingTests()

// MARK: - 每日流量追踪
runTrafficTrackerTests()

// MARK: - 性能热点修复（状态带签名早退 / 心跳退避）
runTransferBandSignatureTests()
runDiscoveryHeartbeatPolicyTests()

// MARK: - 时区与货币配置
runDatabaseConfigTests()

// MARK: - AppEvents 事件总线
runAppEventsTests()

// MARK: - 设置页目录偏好（截图快速保存 / 互传接收）
runSettingsDirectoryTests()

// MARK: - 日志脱敏（OSLog 全量 public，用户路径 / PIN 必须先脱敏）
runLogRedactionTests()

// MARK: - 额度时间格式（跟随系统 12/24 小时制）
runBillingTimeFormatTests()

// MARK: - 开机自启动登记自愈（判定矩阵 / 隔离 suite 上的重新登记与回滚）
runLaunchAtStartupTests()

// MARK: - 通知与音效（事件表 / 声音解析 / 偏好合并 / 音效文件校验 / 额度恢复）
runNotificationTests()
runBillingNotificationMappingTests()

// MARK: - 内建音（合成器确定性 / 时长与峰值 / AIFF 容器 / 存储值契约 / 落盘幂等）
runCueSoundSynthTests()
runCueSoundStoreTests()
runCueSoundMigrationTests()

// MARK: - 本地加密凭据存储（密文落盘 / 历史明文就地加密 / 换机器降级）
runEncryptedSecretStoreTests()
runLocalKeyMaterialTests()

// MARK: - Token 时间口径说明（界面必须写明不跟随系统时区）
runTokenTimeZoneNoteTests()

// MARK: - 凭据存储安全性（默认实现不得删凭据 / 独立存储才搬迁）
runCredentialStorageSafetyTests()
runCredentialMigrationTests()

// MARK: - 剪贴板访问权限状态（文案 / 色调 / 跳转）
runClipboardAccessTests()

// MARK: - 系统权限状态机（三类 × 三态 → 灯色 / 文案 / 重启提示 / 手动添加引导）
runSystemPermissionTests()

// MARK: - 剪贴板：哈希 / 忽略判定 / 模糊搜索
runClipboardHashTests()
runClipboardFuzzySearchTests()

// MARK: - 剪贴板：仓储 / 全文检索 / 超限清理 / 未初始化容错
runClipboardRepositoryTests()
runClipboardFullTextSearchTests()
runClipboardLimitsTests()
runClipboardUninitializedTests()
runClipboardBindingLifetimeTests()

// MARK: - 剪贴板：面板数据流与相对时间
runClipboardPanelMockTests()
runClipboardRelativeTimeTests()

// MARK: - 剪贴板：图片像素守卫与落盘（内存护栏）
runClipboardImagePolicyTests()
runClipboardImageStoreTests()
// 卡片流滑动窗口（内存削减口径）
runClipboardCardWindowTests()

// MARK: - 剪贴板：图片磁盘回收（删除 / 清空 / 超限清理 / 孤儿清扫）
runClipboardImageGCTests()

// MARK: - 剪贴板：文本内容类型判定（类型标签 / 卡片图标共用口径）
runClipboardTextClassifierTests()

// MARK: - 剪贴板：文件条目类型细分（卡片图标 / 无障碍标签）
runClipboardFileClassifierTests()

// MARK: - 剪贴板：文件条目按分类聚合摘要（单文件 / 跨族顺序 / 同族合并 / 按条目边界截断）
runClipboardFileSummaryTests()

// MARK: - 剪贴板：图片存储占用统计（目录不存在 / 空目录 / 计数与字节 / 子目录不计入）
runClipboardStorageUsageTests()

// MARK: - 剪贴板：图片格式兼容（白名单 / 归一化 / 兜底 / 三表示编码）
runClipboardImageFormatTests()

// MARK: - 菜单面板取数口径
runMenuPanelMetricsTests()
runSystemMetricsTests()

// MARK: - 系统页 v2 色板与二级详情页口径
runSystemPaletteTests()
runSystemDetailFormattingTests()
runSystemProcessBoardTests()

// MARK: - Wi-Fi 链路（信号分档 / 信道频率 / 占位值降级）
runWiFiLinkTests()
runWiFiLinkFormattingTests()

// MARK: - 局域网文件互传
runTransferTests()

// MARK: - 扫码接收（二维码 + 浏览器直传）
runScanTests()

// MARK: - 额度页 / Token 页视觉口径（Hero 派生 / 数值单位分列 / 卡片排布）
runBillingHeroLogicTests()
runPaneValueFormattingTests()
runPaneCardLayoutTests()
runPaneValueSizingTests()
runBillingEmptyStateLogicTests()
runBillingPercentDisplayTests()

// MARK: - 计费额度（provider 抽象 + Ollama 响应解码）
runBillingTests()

// MARK: - 额度页可见性（未配置 provider 不占位）+ 同一实例唯一配置
runBillingVisibilityTests()

// MARK: - 额度 Provider 多实例（实例标识 / 实例存储 / 装饰器 / 注册表 / 老配置零迁移）
runBillingInstanceTests()

// MARK: - 屏幕活动（锁屏 / 休眠暂停额度刷新）与快照暂停态
runScreenActivityRelayTests()

// MARK: - 数值单位（设置项 + 万/亿化简口径）
runNumberUnitTests()

// MARK: - 菜单栏显示口径（布局 / 单位 / 刷新周期 / 分页可见性重算）
runMenuBarDisplayTests()

// MARK: - 设置项自定义排序（顺序编解码 / 菜单栏默认上屏顺序 / 旧 Int 键迁移）
runSettingsOrderTests()

// MARK: - 额度阈值提醒（5%/4%/3%/2%/1%）
runBillingAlertTests()

// MARK: - 额度用尽与恢复（用尽后恢复 / 没用尽必静默）
runBillingExhaustionTests()

// MARK: - 额度恢复（回升 / 偏好 / 老状态 JSON 兼容 / 冷却）
runBillingRecoveryTests()

// MARK: - Open Design 额度（归一化 / 工作区发现 / 窗口映射 / 用量聚合）
runOpenDesignBillingTests()
runOpenDesignUsageTests()

// MARK: - OpenCode Go 额度（三窗口已用→剩余 / 限流角标 / 新旧字段兼容 / 错误映射）
runOpencodeGoBillingTests()

// MARK: - 三家新 provider（Claude / Codex / Cursor）解码 + 401/403/解析失败姿态
runBillingProviderDecodingTests()

// MARK: - DSH token 数据层（会话扫描 / 增量索引 / 聚合快照）
runHarnessTokenTests()
runHarnessStreamMemoryTests()
runHarnessTokenIndexTests()
runHarnessTokenHourlyTests()
runHarnessStreamMemoryRegressionTests()

// MARK: - Token tab 展示口径（范围窗口 / 缺省小时 / 环比 / 空态）
runTokenPaneTests()

// MARK: - Token 页展示层（下沉到 Core 的派生计算 / 格式化 / 模型装配）
runTokenDeriveTests()
runTokenPresentationTests()

// MARK: - Token 页「按项目 / 按模型」随范围（与 Hero 同口径）
runTokenRangeConsistencyTests()

// MARK: - Token 分布行 / 占比条悬停文案（同名模型的 provider 可辨识）
runTokenHoverTipTests()

// MARK: - Token 分屏契约（4 屏标题 / 区块唯一归属 / 屏页脚）
runTokenScreenTests()

// MARK: - Token 排行屏汇总块（维度合计 / 与占比分母同源）
runTokenDistroTotalsTests()

// MARK: - 截图选区几何（多屏 / Retina / 归一化）
runSnipGeometryTests()

// MARK: - 截图选区交互状态机
runSnipSelectionStateTests()

// MARK: - 窗口检测命中判定
runSnipWindowTests()

// MARK: - 窗口层级白名单（菜单栏 / 程序坞 / 状态栏项，自家面板保留而覆盖层排除）
runSnipWindowLayerTests()

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

// MARK: - 序号标注（工具分层 / 编号递增 / 几何 / 命中）
runSnipNumberAnnotationTests()

// MARK: - OCR 结果整理（阅读顺序 / 置信度过滤 / 换行拼接）
runSnipTextRecognitionTests()

// MARK: - 贴图旋转与镜像
runSnipTransformTests()

// MARK: - 剪贴板内容分类
runSnipClipboardTests()

// MARK: - 贴图内容源（再贴降级为路径文本 / 恢复池上限）
runSnipPinContentSourceTests()

// MARK: - 截图捕获路径降级
runSnipCapturePlannerTests()

// MARK: - 截图快捷键默认值迁移（无修饰键功能键在 macOS 27 不投递）
runSnipHotKeyMigrationTests()

// MARK: - 截图快捷键偏好读写（keyCode 0 是合法值，不得回落到默认）
runSnipHotKeyPreferencesTests()

// MARK: - 截图工具条布局（左右内边距恒等 / 组间带）
runSnipToolBarLayoutTests()

// MARK: - 截图工具条配置（文字提示档 / 组顺序与显隐 / 常驻工具 / 偏好往返）
runSnipToolBarConfigurationTests()

// MARK: - 截图覆盖层键位解析（⌘S / ⌘A 优先级）
runSnipKeyCommandTests()

// MARK: - 截图鼠标手势（单击选窗 vs 拖拽任意选区）
runSnipPointerGestureTests()

// MARK: - 截图键盘拦截白名单（系统快捷键放行）
runSnipKeyboardInterceptionTests()

// MARK: - 截图键盘路由（输入态放行 / 白名单接管）
runSnipKeyboardRoutingTests()

// MARK: - 右键语义（编辑态收笔 / 非编辑态中止截图）
runSnipRightClickTests()

// MARK: - 画笔粗细档位（[ ] 与 1 2 与滚轮同源）
runSnipLineWidthTests()

// MARK: - 贴图窗键位与点击语义（⌘W / 双击 / 中键 / +/- / ⌃+/-）
runPinKeyCommandTests()

// MARK: - Shift 标注约束 / 偏好样式解析 / Del 删除（Snipaste 官方标注语义）
runSnipAnnotationConstraintTests()
runSnipAnnotationStyleResolverTests()
runSnipAnnotationSelectionTests()

// MARK: - 贴图来源纯文本（⌘⇧C 复制纯文本；无来源时明确反馈）
runSnipPinSourceTextTests()

// MARK: - 面板高度预算（五页补齐页头 / 状态带后仍不触发外框滚动）
runPaneHeightBudgetTests()

// MARK: - 面板分页懒装配（冷启动只装配首屏 / 首次切到才建 / 重复切页不重建）
runPaneAssemblyTests()
runBillingRefreshGateTests()
runDrawnRowLayoutTests()
runBillingCellLayoutTests()

// MARK: - 系统页首屏五卡排布（卡头让位 / 卡高与内容区 / 读数条 / 段宽 / 负载纵轴 / 取整合账）
runSystemCardLayoutTests()

// MARK: - 剪贴板动态轮询调度（三档边界 / 归一化 / 停止后不再重排）
runClipboardPollScheduleTests()

// MARK: - 剪贴板卡片几何与命中（自绘卡片的区域位置 / 点哪算哪个区域 / 区域动作一致性）
runClipboardCardGeometryTests()

// MARK: - 自绘交互层纯口径（等步行带命中 / 区域优先级 / 悬停目标推进与归零）
runDrawnInteractionTests()

// MARK: - 自绘位图翻正（flipped 上下文里的镜像变换 / 离屏取样验证上下缘）
runDrawnUnflipTests()

// MARK: - 剪贴板底部详情区（内容口径 / 面板四段几何 / 高度夹紧）
runClipboardDetailStripTests()

// MARK: - 自绘绘制层纯口径（层不透明度 / 阴影换算 / 焦点环路径 / 符号缓存键 / 读屏文案）
runDrawnSurfaceMathTests()

// MARK: - 版本检测（语义化比较 / 状态文案 / 24 小时限频 / Releases 解码与偏好）
runUpdateVersionTests()
runUpdateCheckStateTests()
runUpdateCheckerTests()


// MARK: - 剪贴板缩略图加载闸门（并发上限 / 在途去重 / 额度归还幂等 / reset）
runClipboardThumbnailGateTests()

// MARK: - 剪贴板缩略图失败重试策略（冷却 / 次数上限终态 / markSucceeded / reset）
runClipboardThumbnailRetryPolicyTests()

// MARK: - 剪贴板缩略图兜底降采样出口（比例 / 不放大 / 上限归一化）
runClipboardThumbnailDecodeTests()

// MARK: - 剪贴板删除二次确认（首次 / 窗口内二次 / 超窗 / 打断 / 互不串味）
runClipboardDeleteConfirmTests()

// MARK: - 外观（主题令牌 / 深浅对比度 / 渲染帧率档 / 外观偏好）
runThemeTokenTests()
runThemeContrastTests()
runRenderTierTests()
runRenderTierGlassTests()
runRenderTierGateTests()
runAppearancePreferencesTests()

// MARK: - 进程显示名映射（本应用那行显示「一览」/ 近似名不误伤 / 截断不变形）
runProcessDisplayNameTests()

// MARK: - 设置窗口骨架（定稿度量 / 侧栏三段分组 / 页头胶囊三态与文案）
runSettingsThemeTests()

// MARK: - 读写分队列（只读连接可见性 / 队列排队等待计时）
runDatabaseReadQueueTests()
runDatabaseQueueWaitTests()

// MARK: - Token 聚合降频（索引结束一次 / 无变更零聚合 / 按需补算）
runHarnessAggregateThrottleTests()

// MARK: - 主线程看门狗口径（停顿阈值 / 日志字段与脱敏）
runMainThreadWatchdogPolicyTests()

// MARK: - 最新请求闸门（异步读只渲染最新一次结果）
runLatestRequestGateTests()

// MARK: - 快照冻结时钟（缺省回落 / now 对齐整分钟 / epoch 固定 / 日期键不漂移）
runSnapshotClockTests()

// MARK: - 偏好域迁移（bundle id 变更时的设置搬迁：全量 / 幂等 / 跳过已有 / 空域）
runPreferenceDomainMigrationTests()

// MARK: - Done
print("\n🎉 所有测试通过！")
