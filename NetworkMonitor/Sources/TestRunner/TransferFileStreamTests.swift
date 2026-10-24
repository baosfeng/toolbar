import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · 流式落盘

// 测试函数放宽为 internal：由 TransferTests.swift 的 runTransferTests() 跨文件调度。

// MARK: - 流式落盘

func testFileStream() {
    print("\n🧪 Testing FileStreamWriter / FileStreamReader...")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("transfer-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let finalURL = directory.appendingPathComponent("hello.txt")
    let expectedDigest = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"  // "hello world"

    // 第一次：写前 5 字节后中断
    do {
        let writer = try FileStreamWriter(finalURL: finalURL)
        try writer.write(Data("hello".utf8))
        assertEqual(writer.totalWritten, 5, "首次写入 5 字节")
        _ = try writer.finish()
    } catch {
        print("❌ 第一次写失败：\(error)")
        exit(1)
    }
    let partURL = UploadPlanner.partURL(for: finalURL)
    assertEqual(FileManager.default.fileExists(atPath: partURL.path), true, ".part 已生成")
    assertEqual(FileStreamReader.size(of: partURL), 5, ".part 大小为 5")

    // 第二次：从 offset 5 续传
    do {
        let writer = try FileStreamWriter(finalURL: finalURL, resumeOffset: 5)
        try writer.write(Data(" world".utf8))
        let digest = try writer.finish()
        assertEqual(digest, expectedDigest, "续传后整文件 sha256 正确")
        assertEqual(writer.totalWritten, 11, "续传后总长 11")
    } catch {
        print("❌ 续传失败：\(error)")
        exit(1)
    }

    // 摘要与独立读取实现一致
    assertEqual(try? FileStreamReader.sha256(of: partURL), expectedDigest, "FileStreamReader 摘要一致")
    assertEqual(FileStreamReader.size(of: partURL), 11, ".part 累计 11 字节")

    // 分块读取
    var collected = Data()
    try? FileStreamReader.readChunks(url: partURL, from: 0, chunkSize: 4) { collected.append($0) }
    assertEqual(String(data: collected, encoding: .utf8), "hello world", "分块读取内容正确")
    assertEqual(FileStreamReader.mimeType(for: URL(fileURLWithPath: "/tmp/a.jpg")), "image/jpeg", "MIME 推断")
    assertEqual(FileStreamReader.mimeType(for: URL(fileURLWithPath: "/tmp/a.unknown")),
                "application/octet-stream", "未知扩展名回落")

    // discard 清理 .part
    do {
        let writer = try FileStreamWriter(finalURL: directory.appendingPathComponent("tmp.bin"))
        try writer.write(Data([1, 2, 3]))
        writer.discard()
    } catch {
        print("❌ discard 测试失败：\(error)")
        exit(1)
    }
    assertEqual(FileManager.default.fileExists(
        atPath: UploadPlanner.partURL(for: directory.appendingPathComponent("tmp.bin")).path),
                false, "discard 删除 .part")
}
