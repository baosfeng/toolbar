import Foundation
import NetworkMonitorCore

// MARK: - 内置解码真实索引自证（人工触发，不参与默认测试流程）
//
// 用法（PATH 里刻意没有 zstd，模拟第三方机器）：
//   env PATH=/usr/bin:/bin .build/arm64-apple-macosx/debug/TestRunner --harness-bundled-probe <Resources 目录>
//
// 判据：能真实解压会话文件并索引出事件，且可用性显示走的是内置解码。

func runHarnessBundledProbe(resourcesDirectory: String) {
    print("probe_bundled_dir = " + resourcesDirectory)
    print("probe_PATH = " + (ProcessInfo.processInfo.environment["PATH"] ?? "<nil>"))
    let zstdOnPath = HarnessZstdLocator.locate(candidates: ["/nonexistent/zstd"],
                                               searchPath: ProcessInfo.processInfo.environment["PATH"],
                                               bundledDirectory: nil,
                                               loginShellLookup: false)
    print("probe_zstd_on_PATH = " + (zstdOnPath ?? "<none>"))

    let streamer = HarnessZstdLineStreamer(executableCandidates: ["/nonexistent/zstd"],
                                           searchPath: nil,
                                           bundledDirectory: resourcesDirectory,
                                           loginShellLookup: false,
                                           logger: ConsoleLogger())
    print("probe_availability = " + streamer.availability.displayMessage)

    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let scanner = HarnessSessionScanner(streamer: streamer)
    let service = HarnessUsageService(scanner: scanner, store: store, logger: ConsoleLogger())
    let done = DispatchSemaphore(value: 0)
    service.rebuildIndex(scope: .full, completion: { _ in done.signal() })
    _ = done.wait(timeout: .now() + 300)

    let snapshot = service.snapshot()
    print("probe_sessions = " + String(snapshot.totalSessions))
    print("probe_indexed_sessions = " + String(snapshot.indexedSessions))
    print("probe_events = " + String(store.harnessEventCount()))
    print("probe_requests_all_time = " + String(snapshot.totals.allTime.requestCount))
    print("probe_state = " + snapshot.indexingState.logLabel)
    if store.harnessEventCount() > 0 {
        print("✅ 内置解码索引成功（无需系统 zstd）")
    } else {
        print("❌ 内置解码未索引出事件")
    }
}
