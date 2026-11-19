import Foundation

// MARK: - TestRunner 入口
//
// 只保留入口与套件调度：用例在各 *Tests.swift，断言辅助在 AssertionHelpers.swift。
// 顶层语句只允许在本文件（SPM 约束）；每域一个登记函数，见 TestSuites+<域>.swift。
// 新增测试文件 = 在对应域的登记函数里加一行，**不需要改本文件**——本文件不再随测试增长；
// 未登记的套件由 TestSuiteRegistrationTests 判红（登记表可校验，不靠人记）。

// MARK: - 人工触发的探针入口（按天清理 / 内置解码 / 索引基准 / 网络）
// 参数解析集中在 ManualProbes.swift，命中即执行并退出，不参与默认测试流程
runManualProbesIfRequested()

// MARK: - Core 域：格式化 / 配置 / 事件总线 / 通知 / 凭据 / 数据库队列 / 版本与偏好迁移
runCoreSuites()

// MARK: - 剪贴板域：仓储 / 搜索 / 卡片 / 图片 / 清理
runClipboardSuites()

// MARK: - 截图与贴图域：选区 / 标注 / 工具条 / 贴图窗
runSnipSuites()

// MARK: - 额度域：provider / 窗口 / 提醒 / 多实例
runBillingSuites()

// MARK: - Token 域：DSH 事件流索引 / 派生口径 / 四屏契约
runTokenSuites()

// MARK: - 面板与外观域：分页装配 / 自绘层 / 主题 / 面板高度
runPaneSuites()

// MARK: - 系统监控与权限域：采样 / 读屏守卫 / 看门狗
runSystemSuites()

// MARK: - 互传与扫码域：发现 / 传输 / 扫码接收
runTransferSuites()

// MARK: - Done
// 失败汇总与退出码由这个唯一出口处理：全绿打印 🎉 并 exit(0)，有失败打印汇总并 exit(1)
TestAssertions.finish()
