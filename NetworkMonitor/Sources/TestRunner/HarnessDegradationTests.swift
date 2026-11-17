import Foundation
import NetworkMonitorCore

// MARK: - Harness zstd 降级路径
//
// 从 HarnessTokenIndexTests.swift 拆出（单文件 500 行 / 15360 字节门禁）：
// 这里只关心「来源全不可用时如何降级」，与聚合口径 / 快照裁剪互不相关。

// MARK: - zstd 缺失降级

private func testHarnessZstdMissingDegradation() {
    // 关闭全部兜底来源（内置解码 / 包内自带 / 登录 shell）：本机装了 zstd 或带着 libzstd 时，
    // 这些来源会让探测必然命中，降级路径就测不到了（生产口径仍默认开启）
    let streamer = HarnessZstdLineStreamer(executableCandidates: ["/nonexistent/zstd"],
                                           searchPath: "",
                                           bundledDirectory: nil,
                                           loginShellLookup: false,
                                           preferBuiltInDecoder: false,
                                           logger: ConsoleLogger())
    assertEqual(streamer.availability.isAvailable, false, "找不到 zstd 不可用")
    guard case .toolMissing(let searched) = streamer.availability else {
        harnessFail("应返回 toolMissing")
    }
    assertEqual(searched.contains("/nonexistent/zstd"), true, "记录探测路径")

    let root = makeTempSessionsRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let scanner = HarnessSessionScanner(sessionsRoot: root, streamer: streamer)
    assertEqual(scanner.availability, streamer.availability, "扫描器继承可用性")

    let file = HarnessSessionFile(path: "/stub/session.v4.jsonl.zstd", sessionID: "s1", size: 1, mtimeMs: 1)
    do {
        _ = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        harnessFail("zstd 缺失时扫描应抛错")
    } catch let error as HarnessTokenError {
        guard case .sourceUnavailable = error else {
            harnessFail("应抛 sourceUnavailable，实际 \(error)")
        }
    } catch {
        harnessFail("应抛 HarnessTokenError，实际 \(error)")
    }

    let db = DatabaseManager()
    db.initializeInMemory()
    let service = HarnessUsageService(scanner: scanner, store: db, logger: ConsoleLogger())
    waitForIndex { service.refreshIfNeeded(completion: $0) }
    guard case .failed(let message) = service.state else {
        harnessFail("zstd 缺失状态应为 failed")
    }
    assertEqual(message.isEmpty, false, "失败原因非空")
    assertEqual(service.snapshot().sourceAvailability, streamer.availability, "快照带出可用性")
    print("✅ Harness zstd 缺失降级 works")
}

// MARK: - 入口

func runHarnessDegradationTests() {
    print("\n🧪 Testing Harness zstd 缺失降级...")
    testHarnessZstdMissingDegradation()
}
