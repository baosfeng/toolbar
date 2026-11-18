import Foundation

// MARK: - 人工触发的自证探针入口
//
// 这些探针靠命令行参数显式触发，命中即执行并退出，不进入默认测试流程。
// 解析与调度集中在此，`main.swift` 只保留一行调用，避免入口文件被参数分支撑大。

/// 按命令行参数执行人工探针；未命中任何参数时立即返回，继续跑默认测试。
func runManualProbesIfRequested() {
    let arguments = CommandLine.arguments

    // 按天清理 → 重扫自证：--harness-purge-probe <资源目录> <天数>
    if let index = arguments.firstIndex(of: "--harness-purge-probe"),
       index + 2 < arguments.count,
       let days = Int(arguments[index + 2]) {
        runHarnessPurgeProbe(resourcesDirectory: arguments[index + 1], days: days)
        exit(0)
    }

    // 内置 zstd 解码自证：--harness-bundled-probe <资源目录>
    if let index = arguments.firstIndex(of: "--harness-bundled-probe"),
       index + 1 < arguments.count {
        runHarnessBundledProbe(resourcesDirectory: arguments[index + 1])
        exit(0)
    }

    // 真实索引基准
    if arguments.contains("--harness-index") {
        runHarnessIndexBenchmark()
        exit(0)
    }

    // 真实网络自证（检查更新）
    if arguments.contains("--update-check-live") {
        runUpdateCheckLiveProbe()
        exit(0)
    }

    // 剪贴板容量上限真实链路自证：--clipboard-capacity-probe <目录>
    if let index = arguments.firstIndex(of: "--clipboard-capacity-probe"),
       index + 1 < arguments.count {
        runClipboardCapacityProbe(directory: arguments[index + 1])
        exit(0)
    }

    // 单位对照表（改前 → 改后）
    if arguments.contains("--number-unit-table") {
        runNumberUnitTable()
        exit(0)
    }
}
