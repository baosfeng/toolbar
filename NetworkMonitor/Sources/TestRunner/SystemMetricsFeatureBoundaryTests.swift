import Foundation
import NetworkMonitorCore
import NetworkMonitorFeatureSystemMetrics

// MARK: - 系统监控服务层（独立 target）边界测试

/// 跨 target 断言：CPU / 磁盘的差分采样入口与「5 秒慢节拍闸门」住在新拆出的
/// `NetworkMonitorFeatureSystemMetrics` 里，TestRunner 直接 import 该模块、走真实入口。
///
/// 改造前测不到：服务层在可执行 target `NetworkMonitor` 里，TestRunner 对
/// `SystemMonitor` 与各采样器完全不可见，只能断言 Core 的判据
/// （`SystemMetricsCalculations` 的纯函数）；「采样器真的按判据封装、且首帧留 nil」
/// 这一层没有任何机器判据。这里补两类：
/// 1) 行为：CPU 每核差分、磁盘速率 / IOPS / 繁忙度、慢节拍闸门，口径与拆分前一致；
/// 2) 边界：源码层面 App target 里不再有 `SystemMetrics/`，新 target 不 import AppKit，
///    且 `final class SystemMonitor` 在新 target 只定义一次（整搬，不是复制一份）。
@MainActor
func runSystemMetricsFeatureBoundaryTests() {
    print("\n🧪 Testing 系统监控服务层跨 target 边界（差分口径 / 慢节拍闸门 / 源码边界）...")
    testMonitorRequiresInjectedLogger()
    testSlowSampleGateInFeatureTarget()
    testCPUDiffInFeatureTarget()
    testDiskDiffInFeatureTarget()
    testSourceBoundaries()
    print("✅ 系统监控服务层跨 target 边界 works")
}

// MARK: - 依赖注入（logger 必传）

/// 记录降级日志的替身：只数条数，不落 ConsoleLogger，避免测试输出被采样失败项污染
/// （TestRunner 里已有一个 `RecordingLogger`，这里按域起名，不抢同名）
private final class SystemMetricsBoundaryLogger: LoggingService, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func log(_ level: LogLevel, _ message: String) {
        lock.lock()
        buffer.append(message)
        lock.unlock()
    }
}

@MainActor
private func testMonitorRequiresInjectedLogger() {
    let logger = SystemMetricsBoundaryLogger()
    // 这行能编译即证明两件事：SystemMonitor 的构造器已跨 target 公开；
    // 且 logger 没有默认值（不再默认取 App 层的 AppContext.shared.logger）。
    let monitor = SystemMonitor(interval: 1, logger: logger)
    // 经 Core 的公共协议持有：@preconcurrency 一致性也随 target 一起搬走了
    let service: any SystemMonitoringService = monitor

    assertEqual(service.snapshot == nil, true, "首帧采样完成前快照为 nil（不把未知显示成 0）")
    assertEqual(SystemMonitor.slowSampleInterval, 5, "慢节拍固定 5 秒档（不是另起定时器）")
    assertEqual(logger.recorded.isEmpty, true, "仅构造不采样时不产生任何日志")
}

// MARK: - 慢节拍闸门

@MainActor
private func testSlowSampleGateInFeatureTarget() {
    let now = Date(timeIntervalSince1970: 1_000)
    assertEqual(SystemMonitor.shouldRunSlowSample(now: now, lastSlowDate: nil), true,
                "首帧没有慢采时刻即放行")
    assertEqual(SystemMonitor.shouldRunSlowSample(now: now,
                                                  lastSlowDate: now.addingTimeInterval(-4.9)), false,
                "距上次 4.9 s 未到点（1 秒档帧不顺带慢采）")
    assertEqual(SystemMonitor.shouldRunSlowSample(now: now,
                                                  lastSlowDate: now.addingTimeInterval(-5)), true,
                "整 5 s 到点放行")
    assertEqual(SystemMonitor.shouldRunSlowSample(now: now,
                                                  lastSlowDate: now.addingTimeInterval(-30)), true,
                "远超间隔仍放行")
    // 时钟回拨（上次慢采时刻在未来）按放行处理：宁可多采一帧，也不让慢节拍永久停摆
    assertEqual(SystemMonitor.shouldRunSlowSample(now: now,
                                                  lastSlowDate: now.addingTimeInterval(4.9)), true,
                "上次时刻在未来（时钟回拨）→ 放行")
}

// MARK: - CPU 差分口径

@MainActor
private func testCPUDiffInFeatureTarget() {
    // 每核 4 槽位 [user, system, idle, nice]；两核增量分别是 150/200、100/100
    let previous = CPUTickBaseline(ticks: [100, 100, 800, 0, 50, 50, 900, 0])
    let current: [UInt32] = [200, 150, 850, 0, 100, 100, 900, 0]
    let snapshot = SystemCPUSampler.snapshot(previous: previous,
                                             current: current,
                                             coreCounts: (performance: 8, efficiency: 2))

    assertNotNil(snapshot, "两帧 tick 齐备即算出快照")
    assertEqual(snapshot?.perCore, [0.75, 1.0], "每核利用率 = (user+system+nice)/全部 的增量比")
    assertEqual(snapshot?.performanceCores, 8, "P 核数原样带出（不在采样器里另算）")
    assertEqual(snapshot?.efficiencyCores, 2, "E 核数原样带出")
    assertEqual(isClose(snapshot?.totalUsage, 250.0 / 300.0), true, "总利用率按全部核增量合并")
    assertEqual(isClose(snapshot?.userUsage, 150.0 / 300.0), true, "用户态占比同源")
    assertEqual(isClose(snapshot?.systemUsage, 100.0 / 300.0), true, "系统态占比同源")

    assertEqual(SystemCPUSampler.snapshot(previous: nil,
                                          current: current,
                                          coreCounts: (performance: 8, efficiency: 2)) == nil, true,
                "无基线首帧返回 nil（留空而不是 0）")
    assertEqual(SystemCPUSampler.snapshot(previous: CPUTickBaseline(ticks: [1, 2, 3]),
                                          current: current,
                                          coreCounts: (performance: 8, efficiency: 2)) == nil, true,
                "tick 长度不是 4 的倍数 → nil（数据形态不合法不猜）")
}

// MARK: - 磁盘差分口径

@MainActor
private func testDiskDiffInFeatureTarget() {
    let baseline: DiskTransferTable = [1: DiskIOCounters()]
    let current: DiskTransferTable = [1: DiskIOCounters(readBytes: 1_000_000_000,
                                                        writeBytes: 500_000_000,
                                                        readOperations: 200,
                                                        writeOperations: 100,
                                                        readTotalTime: 500_000_000,
                                                        writeTotalTime: 250_000_000)]
    let throughput = SystemDiskSampler.throughput(previous: baseline, current: current, elapsed: 2)

    assertNotNil(throughput, "两帧计数齐备即算出吞吐")
    assertEqual(throughput?.readBytesPerSecond, 500_000_000, "读速率 = 增量 / elapsed")
    assertEqual(throughput?.writeBytesPerSecond, 250_000_000, "写速率 = 增量 / elapsed")
    assertEqual(throughput?.readIOPS, 100, "读 IOPS = 操作数增量 / elapsed")
    assertEqual(throughput?.writeIOPS, 50, "写 IOPS = 操作数增量 / elapsed")
    assertEqual(throughput?.busyFraction, 0.375, "繁忙度 =（读写服务时间纳秒→秒）/ elapsed")

    assertEqual(SystemDiskSampler.throughput(previous: nil, current: current, elapsed: 2) == nil, true,
                "首帧无基线 → nil（不把未知写成 0）")
    assertEqual(SystemDiskSampler.throughput(previous: baseline, current: current, elapsed: 0) == nil, true,
                "时间差 0 → nil（除零保护）")
    assertEqual(SystemDiskSampler.throughput(previous: [7: DiskIOCounters()],
                                             current: current,
                                             elapsed: 2) == nil, true,
                "没有任何 entryID 配得上 → nil")

    // 拔盘：只在 current 出现的 entryID 不计入，也不让整帧变 nil
    var withExtraDisk = current
    withExtraDisk[2] = DiskIOCounters(readBytes: 999_999_999_999)
    let afterUnplug = SystemDiskSampler.throughput(previous: baseline,
                                                   current: withExtraDisk,
                                                   elapsed: 2)
    assertEqual(afterUnplug?.readBytesPerSecond, 500_000_000,
                "只累加两次都存在的 entryID（按注册表 ID 配对，不按下标）")
}

// MARK: - 源码边界（拆干净）

@MainActor
private func testSourceBoundaries() {
    let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // TestRunner
        .deletingLastPathComponent()   // Sources
    let appMetricsDirectory = sourcesRoot.appendingPathComponent("NetworkMonitor/SystemMetrics").path
    assertEqual(FileManager.default.fileExists(atPath: appMetricsDirectory), false,
                "App target 里不再有 SystemMetrics 目录（14 个文件已整体搬走）")

    let featureDirectory = sourcesRoot.appendingPathComponent("NetworkMonitorFeatureSystemMetrics")
    let featureFiles = ((try? FileManager.default.contentsOfDirectory(atPath: featureDirectory.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()
    assertEqual(featureFiles.count, 14, "新 target 里是同一个 14 文件集合")
    assertEqual(featureFiles.contains("SystemMonitor.swift"), true, "采样服务主文件在新 target")
    assertEqual(featureFiles.contains("SystemMonitor+SlowMetrics.swift"), true, "慢节拍扩展同族一起搬")

    let appKitImports = featureFiles.filter { file in
        let text = (try? String(contentsOf: featureDirectory.appendingPathComponent(file),
                                encoding: .utf8)) ?? ""
        return text.contains("import AppKit")
    }
    assertEqual(appKitImports, [], "新 target 不依赖 AppKit（只有 Darwin / IOKit / CoreWLAN / Foundation / Core）")

    let featureDefinesMonitor = featureFiles.filter { file in
        let text = (try? String(contentsOf: featureDirectory.appendingPathComponent(file),
                                encoding: .utf8)) ?? ""
        return text.contains("final class SystemMonitor")
    }
    assertEqual(featureDefinesMonitor, ["SystemMonitor.swift"], "SystemMonitor 在新 target 只定义一次")

    // 与验收判据同一条：grep -rn 'final class SystemMonitor' Sources/NetworkMonitor/ 应为 0
    let appDefinesMonitor = swiftFiles(under: sourcesRoot.appendingPathComponent("NetworkMonitor"))
        .filter { $0.text.contains("final class SystemMonitor") }
        .map(\.relativePath)
    assertEqual(appDefinesMonitor, [], "App target 里不再定义 SystemMonitor（没有留副本）")
}

/// 递归列出 Swift 源码（只读路径与正文，供源码边界断言用）
private func swiftFiles(under root: URL) -> [(relativePath: String, text: String)] {
    guard let enumerator = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil) else {
        return []
    }
    let prefix = root.path + "/"
    var files: [(relativePath: String, text: String)] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        files.append((url.path.replacingOccurrences(of: prefix, with: ""), text))
    }
    return files
}

/// 浮点断言：差分口径用相对容差而非位相等（两边的合并顺序不同会影响末位）
private func isClose(_ value: Double?, _ expected: Double) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 1e-9
}
