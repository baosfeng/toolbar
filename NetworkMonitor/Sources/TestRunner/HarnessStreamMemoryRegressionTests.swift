import Foundation
import NetworkMonitorCore

// MARK: - Harness 扫描驻留有界回归测试
//
// 与 HarnessStreamMemoryTests.swift 同属「Token 索引器内存修复」的回归门禁，
// 拆成独立文件是为了同时守住 500 行 / 15360 字节的文件门禁。
//
// 背景：Token 全量重建曾在一个 GCD 块里逐行 JSONSerialization 解析且没有 autoreleasepool，
// 自动释放对象直到整个重建结束才回收，驻留量随已解析字节数单调增长。
// 修复后驻留应与文件大小无关。
//
// 夹具与辅助函数（harnessFootprintMB / harnessUsageLine / harnessCompress /
// harnessZstdPath / harnessTempDirectory / HarnessPeakSampler）见 HarnessStreamMemoryTests.swift。

// MARK: - 4. 驻留有界（核心回归）
//
// 在一个 GCD 块内扫描一份远超 64KB 的会话文件：
// 修复前自动释放对象挂在线程顶层池，直到块结束才回收，驻留随字节数线性增长；
// 修复后应在常数级（几 MB）内收敛。阈值取 24MB——修复前同规模约 +100MB。

private func testHarnessScanResidencyBounded() {
    guard let zstd = harnessZstdPath() else {
        print("⏭  跳过驻留有界：无 zstd")
        return
    }
    let directory = harnessTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let plainPath = directory + "/session.jsonl"
    let archivePath = directory + "/session.v4.jsonl.zstd"
    // 约 48MB 明文、约 1.2 万行，行均 ~4KB（贴近真实会话）：修复前驻留约 +50MB
    var buffer = #"{"type":"session","cwd":"/tmp/lab/residency"}"# + "\n"
    let targetBytes = 48 * 1024 * 1024
    var tsMs: Int64 = 1_700_000_000_000
    var generated = 0
    while buffer.utf8.count < targetBytes {
        buffer += harnessUsageLine(tsMs: tsMs, input: 100 + generated % 7, output: 50 + generated % 5, padding: 3900) + "\n"
        tsMs += 1000
        generated += 1
    }
    guard (try? buffer.write(toFile: plainPath, atomically: true, encoding: .utf8)) != nil,
          harnessCompress(zstdPath: zstd, from: plainPath, to: archivePath) else {
        harnessFail("驻留有界：夹具准备失败")
        return
    }
    let expectedEvents = generated
    buffer = ""

    // 与生产一致的执行上下文：整个重建跑在单个 GCD 块里
    let scanner = HarnessSessionScanner(sessionsRoot: directory, streamer: HarnessZstdLineStreamer())
    let file = HarnessSessionFile(path: archivePath, sessionID: "residency", size: 0, mtimeMs: 0, members: [archivePath])

    let semaphore = DispatchSemaphore(value: 0)
    final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var value: HarnessSessionScanResult?
        private var failure: String?
        func set(result: HarnessSessionScanResult) { lock.lock(); value = result; lock.unlock() }
        func set(failure: String) { lock.lock(); self.failure = failure; lock.unlock() }
        var snapshot: (HarnessSessionScanResult?, String?) { lock.lock(); defer { lock.unlock() }; return (value, failure) }
    }
    let outcome = Outcome()

    let baseline = harnessFootprintMB()
    let sampler = HarnessPeakSampler()
    sampler.start()
    DispatchQueue.global().async {
        do {
            let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
            outcome.set(result: result)
        } catch {
            outcome.set(failure: String(describing: error))
        }
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 600) == .timedOut {
        _ = sampler.stop()
        harnessFail("驻留有界：扫描超时")
        return
    }
    let peak = sampler.stop()
    let (result, failure) = outcome.snapshot
    if let failure { harnessFail("驻留有界：扫描失败 \(failure)") }
    guard let result else {
        harnessFail("驻留有界：无扫描结果")
        return
    }

    let delta = peak - baseline
    // 行数口径说明：读取循环在「块以换行结尾」时会多产出一个尾随空行，
    // 这是修复前既有行为（已用复刻的旧算法逐字节比对确认），不属于本次改动范围，
    // 因此这里只断言下界与解析结果，不对空行个数做脆弱断言。
    assertEqual(result.totalLines >= expectedEvents, true, "驻留有界：总行数不少于 usage 行数")
    assertEqual(result.events.count, expectedEvents, "驻留有界：事件数")
    assertEqual(result.malformedLines, 0, "驻留有界：无坏行")
    // 修复前同规模驻留约等于明文体积；修复后应远小于它
    let limitMB = 24.0
    print(String(format: "   footprint baseline=%.1fMB peak=%.1fMB delta=+%.1fMB (limit %.0fMB, 明文 %.0fMB)",
                 baseline, peak, delta, limitMB, Double(targetBytes) / 1024.0 / 1024.0))
    if delta > limitMB {
        print("❌ 驻留随文件大小增长：delta=+\(String(format: "%.1f", delta))MB > \(limitMB)MB —— 逐行/块级 autoreleasepool 可能失效")
        exit(1)
    }
    print("✅ 驻留有界 works")
}

// MARK: - 5. 病态超长单行（防 O(n²) 复发）
//
// 真实库里存在一行 14MB 的 tool/ptc-dispatch 事件（整份文件才 56MB）。
// 曾经的写法每读到一块就把「已累积半行 + 整块」拼接后整体切分，
// 于是一行跨几百块时产生 O(行长²) 次拷贝：实测该文件峰值 471MB，
// 且加了块级 autoreleasepool 后反而涨到 763MB（池让中间 Data 更快释放，
// 却掩盖了重复整条复制的本质）。改为增量追加后应回落到与单行长度成正比。

private func testHarnessPathologicalLongLine() {
    guard let zstd = harnessZstdPath() else {
        print("⏭  跳过超长单行：无 zstd")
        return
    }
    let directory = harnessTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let plainPath = directory + "/longline.jsonl"
    let archivePath = directory + "/longline.v4.jsonl.zstd"
    // 20MB 单行工具事件 + 少量正常行：行本身不含 usage/cwd，属于「预筛会跳过」的类别，
    // 因此这条用例只考验流式切分，与 JSON 解析无关。
    var buffer = #"{"type":"session","cwd":"/tmp/lab/longline"}"# + "\n"
    buffer += "{\"type\":\"tool/ptc-dispatch\",\"data\":{\"content\":\""
    buffer += String(repeating: "x", count: 20 * 1024 * 1024)
    buffer += "\n"
    buffer += harnessUsageLine(tsMs: 1_700_000_000_000, input: 1, output: 2) + "\n"
    guard (try? buffer.write(toFile: plainPath, atomically: true, encoding: .utf8)) != nil,
          harnessCompress(zstdPath: zstd, from: plainPath, to: archivePath) else {
        harnessFail("超长单行：夹具准备失败")
        return
    }
    buffer = ""

    let scanner = HarnessSessionScanner(sessionsRoot: directory, streamer: HarnessZstdLineStreamer())
    let file = HarnessSessionFile(path: archivePath, sessionID: "longline", size: 0, mtimeMs: 0, members: [archivePath])
    // 必须用峰值采样线程：O(n²) 开销发生在扫描过程中，结束时读一次会漏掉瞬时峰值
    let sampler = HarnessPeakSampler()
    let baseline = harnessFootprintMB()
    sampler.start()
    do {
        let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        let peak = sampler.stop()
        let delta = peak - baseline
        print(String(format: "  超长单行 footprint baseline=%.1fMB peak=%.1fMB delta=+%.1fMB",
                     baseline, peak, delta))
        assertEqual(result.events.count, 1, "超长单行：仍解析出 1 条 usage")
        // 阈值口径：修复后实测 +18MB（20MB 行体 + zstd 缓冲）；
        // 退回「每块拼接整行」的 O(行长²) 写法后实测 +91MB（且已在真机 14MB 单行上见到 471→763MB）。
        // 取 60MB：既能拦住 O(n²) 复发，又给不同 zstd/内存分配器留出余量。
        if delta > 60 {
            print("❌ 超长单行内存异常：delta=+\(String(format: "%.1f", delta))MB > 60MB —— 切分疑似退回 O(行长²)")
            exit(1)
        }
        print("✅ 超长单行不退化 works")
    } catch {
        _ = sampler.stop()
        harnessFail("超长单行：扫描失败 \(error)")
    }
}

// MARK: - 测试入口

func runHarnessStreamMemoryRegressionTests() {
    print("\n🧪 Testing Harness 扫描驻留有界...")
    testHarnessScanResidencyBounded()
    print("✅ Harness 扫描驻留有界 works")
    print("\n🧪 Testing Harness 超长单行切分...")
    testHarnessPathologicalLongLine()
}
