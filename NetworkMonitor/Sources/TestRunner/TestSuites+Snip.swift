import Foundation

// MARK: - 套件登记：Snip 域
//
// 覆盖：选区 / 标注 / 工具条 / 贴图窗
//
// 本域全部测试入口的**唯一登记处**：新增本域测试文件时只在这里加一行调用，
// 不必改 main.swift；顺序即执行顺序，行尾注释是该套件覆盖的口径。
// 忘了登记不会编译报错，但 TestSuiteRegistrationTests 会把「定义了却没人调用」的套件判红。
// @MainActor 与改造前 main.swift 顶层语句同隔离语义（个别套件本身是 @MainActor）。

@MainActor
func runSnipSuites() {
    runSnipGeometryTests()
    runSnipSelectionStateTests()
    runSnipWindowTests()
    runSnipWindowLayerTests()
    runSnipFileTests()
    runSnipHistoryTests()
    runSnipPixelTests()
    runSnipSizeTests()
    runSnipAnnotationTests()
    runSnipComposerTests()
    runSnipMosaicTests()
    runSnipTextTests()
    runSnipNumberAnnotationTests()
    runSnipTextRecognitionTests()
    runSnipTransformTests()
    runSnipPinContentSourceTests()
    runSnipCapturePlannerTests()
    runSnipCaptureMatchingTests()  // 覆盖层 ↔ 捕获图配对：displayID 优先、frame 漂移不失配、单屏兜底
    runSnipHotKeyMigrationTests()
    runSnipHotKeyPreferencesTests()
    runSnipDockIconPolicyTests()
    runSnipPasteboardImageBudgetTests()  // 复制到剪贴板的体积预算（1MB：2x PNG → 1x PNG → JPEG 兜底）
    runSnipToolBarLayoutTests()  // 布局与分隔线比例
    runSnipBarToneTests()  // 选中 / 悬停 / 常态三档明度 + 两级选中语言 + 当前色圆点恒带环
    runSnipToolBarConfigurationTests()
    runSnipToolBarOrderTests()
    runSnipKeyCommandTests()
    runSnipPointerGestureTests()
    runSnipKeyboardInterceptionTests()
    runSnipKeyboardRoutingTests()
    runSnipKeyboardGateTests()
    runSnipKeyboardWiringTests()
    runSnipRightClickTests()
    runSnipLineWidthTests()
    runSnipAnnotationCustomizationTests()  // 文字字号/字重/字体族独立、线宽连续值、颜色 alpha 持久、取色器 HSV 换算
    runSnipNumericTests()  // 数值任意可调：参数表/三档意图步进/滚轮归一化/读数气泡/精确输入/图形缩放/像素效果强度
    runPinKeyCommandTests()
    runSnipAnnotationConstraintTests()
    runSnipAnnotationStyleResolverTests()
    runSnipAnnotationSelectionTests()
    runSnipPinSourceTextTests()
    runPinMenuOrderTests()  // 贴图菜单顺序：归一化口径（缺键回落 / 未知项丢弃 / 新项补尾）
    runPinMenuOrderMoveTests()  // 贴图菜单顺序：分隔线落位 / 上下移动 / 偏好读写不写回
    runPinDefaultAlphaTests()  // 贴图默认透明度：设置页写入 → 新贴图窗生效（缺键 1 / 越界钳制）
    runPinDragSessionTests()
    runPinScrollAdjustmentTests()  // 滚轮换算：拖动/惯性闸 + 按设备步长 + 钳制
    runPinZoomAnchorTests()  // 滚轮缩放以鼠标为锚：锚点归一化位置不变 / 缺省锚点仍是窗口中心
    runPinBoardBackgroundTests()  // 棋盘底：含 alpha 才画 + 开关缺键即关
    runSnipFeatureBoundaryTests()  // 截图服务层拆成 NetworkMonitorFeatureSnip：端口注入 / 写盘与选档 / 热键归一化 / 源码边界
}
