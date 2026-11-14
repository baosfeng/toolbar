import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板图片存储占用统计

/// 覆盖设置页「存储」卡的数据口径：目录不存在 / 空目录 / 有文件 / 子目录不计入
///
/// 统计函数只做 FileManager 读取，这里用临时目录跑真实 IO，不碰真实图片目录。
func runClipboardStorageUsageTests() {
    print("🧪 Testing Clipboard storage usage...")
    runStorageUsageDirectoryTests()
    runStorageUsageCountingTests()
    print("✅ Clipboard 图片存储占用统计（不存在 / 空目录 / 计数与字节 / 子目录不计入）works")
}

// MARK: - 临时目录夹具

private func makeStorageUsageTempDirectory(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipboard-storage-usage-\(name)", isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func writeStorageUsageFile(_ name: String, bytes: Int, in directory: URL) -> URL {
    let url = directory.appendingPathComponent(name)
    try? Data(repeating: 9, count: bytes).write(to: url)
    return url
}

// MARK: - 目录状态

private func runStorageUsageDirectoryTests() {
    // 目录不存在：exists=false，条数与字节归零，不抛错
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipboard-storage-usage-missing", isDirectory: true)
    try? FileManager.default.removeItem(at: missing)
    let missingSummary = ClipboardStorageUsage.summarize(in: missing)
    assertEqual(missingSummary.exists, false, "目录不存在时 exists=false")
    assertEqual(missingSummary.fileCount, 0, "目录不存在时条数为 0")
    assertEqual(missingSummary.byteCount, 0, "目录不存在时字节为 0")

    // 拿「文件」当目录传入同样按不可用处理（contentsOfDirectory 会失败）
    let asFile = makeStorageUsageTempDirectory("as-file").appendingPathComponent("not-a-dir")
    try? Data([1, 2, 3]).write(to: asFile)
    let asFileSummary = ClipboardStorageUsage.summarize(in: asFile)
    assertEqual(asFileSummary.exists, false, "路径是文件而不是目录时 exists=false")

    // 空目录：exists=true，0 条 0 字节
    let emptyDir = makeStorageUsageTempDirectory("empty")
    let emptySummary = ClipboardStorageUsage.summarize(in: emptyDir)
    assertEqual(emptySummary.exists, true, "空目录 exists=true")
    assertEqual(emptySummary.fileCount, 0, "空目录条数为 0")
    assertEqual(emptySummary.byteCount, 0, "空目录字节为 0")
    assertEqual(ClipboardStorageUsage.empty, ClipboardStorageUsage.Summary(fileCount: 0, byteCount: 0, exists: false),
                "empty 常量口径固定")

    print("✅ Clipboard 存储统计（不存在 / 传文件 / 空目录）works")
}

// MARK: - 计数与字节

private func runStorageUsageCountingTests() {
    let directory = makeStorageUsageTempDirectory("counting")
    writeStorageUsageFile("h1.png", bytes: 1024, in: directory)
    writeStorageUsageFile("h1_thumb.png", bytes: 256, in: directory)
    writeStorageUsageFile("h2.jpg", bytes: 4096, in: directory)

    let summary = ClipboardStorageUsage.summarize(in: directory)
    assertEqual(summary.exists, true, "有文件时 exists=true")
    assertEqual(summary.fileCount, 3, "三个文件计 3 条")
    assertEqual(summary.byteCount, UInt64(1024 + 256 + 4096), "字节按文件大小求和")

    // 子目录不计入：目录内再建一层子目录并在其中放文件，统计只认第一层普通文件
    let nested = directory.appendingPathComponent("nested", isDirectory: true)
    try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    writeStorageUsageFile("deep.png", bytes: 8192, in: nested)
    let nestedSummary = ClipboardStorageUsage.summarize(in: directory)
    assertEqual(nestedSummary.fileCount, 3, "子目录自身不计条数")
    assertEqual(nestedSummary.byteCount, UInt64(1024 + 256 + 4096), "子目录内文件不计字节")

    // 删掉一个文件后计数立刻回落（设置页每次刷新现算，不留缓存）
    try? FileManager.default.removeItem(at: directory.appendingPathComponent("h2.jpg"))
    let afterDelete = ClipboardStorageUsage.summarize(in: directory)
    assertEqual(afterDelete.fileCount, 2, "删除后条数回落")
    assertEqual(afterDelete.byteCount, UInt64(1024 + 256), "删除后字节回落")

    // 清理夹具，别在临时目录留垃圾
    try? FileManager.default.removeItem(at: directory)

    print("✅ Clipboard 存储统计（计数 / 字节求和 / 子目录不计入 / 删除后回落）works")
}
