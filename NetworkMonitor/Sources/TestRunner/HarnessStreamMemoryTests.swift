import Foundation
import Darwin
import NetworkMonitorCore

// MARK: - Harness 流式读取内存与分块边界回归测试
//
// 背景：Token 全量重建曾在一个 GCD 块里逐行 JSONSerialization 解析且没有 autoreleasepool，
// 自动释放对象直到整个重建结束才回收，内存随已解析字节数单调增长（实测 86MB 会话 +215MB）。
// 修复点有两处，本文件同时守住：
//   1. HarnessSessionScanner.scan 逐行池 —— JSON 解析中间体按行回收
//   2. HarnessZstdLineStreamer.streamLines 块级池 —— availableData 返回的 NSData 块按块回收
// 另覆盖分块边界（跨块长行、无尾换行）以确保修复没有改变行切分语义。

// MARK: - 内存采样

/// 当前进程物理 footprint（MB）
func harnessFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1024.0 / 1024.0
}

/// 峰值采样线程（测试用，避免把采样线程自身的栈算进被测区间）
final class HarnessPeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = 0.0
    private var running = false

    func start() {
        lock.lock()
        running = true
        lock.unlock()
        let thread = Thread { [weak self] in
            guard let self else { return }
            while self.isRunning {
                let value = harnessFootprintMB()
                self.lock.lock()
                if value > self.peak { self.peak = value }
                self.lock.unlock()
                usleep(10_000)
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func stop() -> Double {
        lock.lock()
        running = false
        lock.unlock()
        // 采样线程退出后再读峰值，避免竞态
        usleep(60_000)
        lock.lock()
        defer { lock.unlock() }
        return peak
    }
}

// MARK: - 夹具

/// 生成临时目录
func harnessTempDirectory() -> String {
    let path = NSTemporaryDirectory() + "harness-stream-tests-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

/// 用系统 zstd 压缩 JSONL（与生产解压路径对称）
@discardableResult
func harnessCompress(zstdPath: String, from plainPath: String, to archivePath: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: zstdPath)
    process.arguments = ["-q", "-f", plainPath, "-o", archivePath]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

/// 组装一条 usage 行（padding 用于撑大单行，验证跨块长行）
func harnessUsageLine(tsMs: Int64, input: Int, output: Int, padding: Int = 0) -> String {
    let filler = padding > 0 ? String(repeating: "x", count: padding) : ""
    let head = "{\"type\":\"assistant/message\",\"time\":\(tsMs),\"data\":{\"usage\":{\"inputTokens\":\(input),"
    let mid = "\"outputTokens\":\(output),\"cacheReadTokens\":1},\"message\":{\"role\":\"assistant\",\"content\":\""
    let tail = "\",\"source\":{\"provider\":\"p\",\"model\":\"m\"}}}}"
    return head + mid + filler + tail
}

/// 实际可用的 zstd（不可用则返回 nil，相关用例跳过）
func harnessZstdPath() -> String? {
    let streamer = HarnessZstdLineStreamer(logger: ConsoleLogger())
    if case .available(let path) = streamer.availability { return path }
    return nil
}

// MARK: - 1. 跨块长行（> 64KB 单次读取块）不被截断
//
// 关键回归：块级 autoreleasepool 重构后，combined / carry 的复制时机若出错，
// 长行会跨块被截成两条，坏行数随之上升。

private func testHarnessLongLineAcrossChunks() {
    guard let zstd = harnessZstdPath() else {
        print("⏭  跳过跨块长行：无 zstd")
        return
    }
    let directory = harnessTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let plainPath = directory + "/session.jsonl"
    let archivePath = directory + "/session.v4.jsonl.zstd"
    // 一条超过 64KB 读取块 4 倍的长行，夹在两条正常行之间
    let longLine = harnessUsageLine(tsMs: 2000, input: 7, output: 8, padding: 256 * 1024)
    let lines = [
        #"{"type":"session","cwd":"/tmp/lab/chunk"}"#,
        harnessUsageLine(tsMs: 1000, input: 1, output: 2),
        longLine,
        harnessUsageLine(tsMs: 3000, input: 3, output: 4),
    ]
    let plain = lines.joined(separator: "\n") + "\n"
    guard (try? plain.write(toFile: plainPath, atomically: true, encoding: .utf8)) != nil,
          harnessCompress(zstdPath: zstd, from: plainPath, to: archivePath) else {
        harnessFail("跨块长行：夹具准备失败")
    }

    let scanner = HarnessSessionScanner(sessionsRoot: directory, streamer: HarnessZstdLineStreamer())
    let file = HarnessSessionFile(path: archivePath, sessionID: "chunk", size: 0, mtimeMs: 0, members: [archivePath])
    do {
        let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        // 带尾换行的 JSONL 会产出一个末尾空行（与修复前算法逐字节一致），故为 4 条内容行 + 1 空行
        assertEqual(result.totalLines, 5, "跨块长行：总行数不变（长行未被切成两行）")
        assertEqual(result.malformedLines, 0, "跨块长行：无坏行")
        assertEqual(result.events.count, 3, "跨块长行：三条 usage 全部解析")
        assertEqual(result.cwd, "/tmp/lab/chunk", "跨块长行：cwd 正确")
    } catch {
        harnessFail("跨块长行扫描失败：\(error)")
    }
}

// MARK: - 2. 无尾换行的最后一行仍被产出
//
// 关键回归：块级池重构把 carry 赋值移进了池内，末行 flush 路径必须仍然可达。

private func testHarnessTrailingLineWithoutNewline() {
    guard let zstd = harnessZstdPath() else {
        print("⏭  跳过无尾换行：无 zstd")
        return
    }
    let directory = harnessTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let plainPath = directory + "/session.jsonl"
    let archivePath = directory + "/session.v4.jsonl.zstd"
    // 刻意不给最后一行加换行符
    let plain = [
        #"{"type":"session","cwd":"/tmp/lab/tail"}"#,
        harnessUsageLine(tsMs: 1000, input: 11, output: 22),
        harnessUsageLine(tsMs: 2000, input: 33, output: 44),
    ].joined(separator: "\n")
    guard (try? plain.write(toFile: plainPath, atomically: true, encoding: .utf8)) != nil,
          harnessCompress(zstdPath: zstd, from: plainPath, to: archivePath) else {
        harnessFail("无尾换行：夹具准备失败")
    }

    let scanner = HarnessSessionScanner(sessionsRoot: directory, streamer: HarnessZstdLineStreamer())
    let file = HarnessSessionFile(path: archivePath, sessionID: "tail", size: 0, mtimeMs: 0, members: [archivePath])
    do {
        let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        assertEqual(result.totalLines, 3, "无尾换行：末行仍计入")
        assertEqual(result.events.count, 2, "无尾换行：末行仍被解析")
        assertEqual(result.malformedLines, 0, "无尾换行：无坏行")
    } catch {
        harnessFail("无尾换行扫描失败：\(error)")
    }
}

// MARK: - 3. 空白行 / 坏行 / 继续计数不变
//
// 关键回归：逐行池包裹 parse 后，各分支计数必须原样累加。

private func testHarnessLineCountersUnchanged() {
    guard let zstd = harnessZstdPath() else {
        print("⏭  跳过计数口径：无 zstd")
        return
    }
    let directory = harnessTempDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let plainPath = directory + "/session.jsonl"
    let archivePath = directory + "/session.v4.jsonl.zstd"
    let plain = [
        #"{"type":"session","cwd":"/tmp/lab/counters"}"#,
        "这不是 JSON",
        "",
        "   ",
        #"{"type":"user/message","time":1500}"#,
        harnessUsageLine(tsMs: 1000, input: 5, output: 6),
        #"{"type":"assistant/message","data":{"usage":{"inputTokens":1}}}"#,
    ].joined(separator: "\n") + "\n"
    guard (try? plain.write(toFile: plainPath, atomically: true, encoding: .utf8)) != nil,
          harnessCompress(zstdPath: zstd, from: plainPath, to: archivePath) else {
        harnessFail("计数口径：夹具准备失败")
    }

    let scanner = HarnessSessionScanner(sessionsRoot: directory, streamer: HarnessZstdLineStreamer())
    let file = HarnessSessionFile(path: archivePath, sessionID: "counters", size: 0, mtimeMs: 0, members: [archivePath])
    do {
        let result = try scanner.scan(file: file, isCancelled: { false }, onLinesRead: nil)
        assertEqual(result.totalLines, 8, "计数口径：总行数（7 条内容行 + 末尾空行）")
        assertEqual(result.malformedLines, 2, "计数口径：坏行 2（非 JSON + 缺 time）")
        // session 行计入 cwd 而不计入 ignored；其余 4 行为空行 / 空白行 / 无关事件 / 末尾空行
        assertEqual(result.ignoredLines, 4, "计数口径：忽略 4（空行 + 空白行 + 无关事件 + 末尾空行）")
        assertEqual(result.events.count, 1, "计数口径：解析出 1 条")
        assertEqual(result.cwd, "/tmp/lab/counters", "计数口径：cwd")
    } catch {
        harnessFail("计数口径扫描失败：\(error)")
    }
}

// MARK: - 测试入口

func runHarnessStreamMemoryTests() {
    print("\n🧪 Testing Harness 流式读取（分块边界 / 计数口径）...")
    testHarnessLongLineAcrossChunks()
    testHarnessTrailingLineWithoutNewline()
    testHarnessLineCountersUnchanged()
    print("✅ Harness 流式读取（分块边界 / 计数口径）works")
}
