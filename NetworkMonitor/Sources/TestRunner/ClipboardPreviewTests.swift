import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 预览项构造（文本 / 图片 / 文件 + 临时目录清理）

/// 预览项构造的守门测试
///
/// 钉住三件事：
/// 1. 三种条目各给对载体 —— 文本写临时 .txt、图片给原图路径、文件给存在的那个路径；
/// 2. 缺内容的边界（空文本 / 原图丢失 / 文件全丢）抛明确错误，不静默给空预览；
/// 3. 临时目录的写与删幂等 —— 退出清理可重复调用，不抛错。
func runClipboardPreviewTests() {
    print("🧪 Testing clipboard preview target...")

    let fileManager = FileManager.default
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("nm-preview-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: directory) }

    // MARK: 文本条目 → 临时 .txt

    let text = "第一行\n第二行：预览正文"
    let textItem = ClipboardItem(kind: .text, text: text, preview: text, contentHash: "preview-text")
    let textTarget = try! ClipboardPreviewBuilder.target(for: textItem, directory: directory)
    assertEqual(textTarget.content == .text(textTarget.content.url), true, "文本条目给临时文本载体")
    assertEqual(textTarget.content.url.pathExtension, "txt", "临时文件扩展名是 txt")
    assertEqual(textTarget.content.url.deletingLastPathComponent().standardizedFileURL.path,
                directory.standardizedFileURL.path, "临时文件落在调用方给的目录里")
    assertEqual(try? String(contentsOf: textTarget.content.url, encoding: .utf8), text, "临时文件内容与正文一致")
    assertEqual(textTarget.characterCount, text.count, "正文字符数上报")
    assertContains(textTarget.title, "文本", "标题带类型名")
    assertContains(textTarget.title, "\(text.count) 字符", "标题带字符数")

    // 同一 id 重复构造 → 同名覆盖，不堆碎片
    let again = try! ClipboardPreviewBuilder.target(for: textItem, directory: directory)
    assertEqual(again.content.url, textTarget.content.url, "同一条目重复预览复用同一个临时文件")
    let files = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    assertEqual(files.count, 1, "目录里只有一份临时文件")

    // MARK: 空文本 → 明确报错

    let empty = ClipboardItem(kind: .text, text: "   \n\t ", preview: "", contentHash: "preview-empty")
    do {
        _ = try ClipboardPreviewBuilder.target(for: empty, directory: directory)
        assertEqual("未抛错", "应抛 emptyText", "空白文本必须报错")
    } catch {
        assertEqual(error as? ClipboardPreviewError, .emptyText, "空白文本抛 emptyText")
    }

    // MARK: 图片条目 → 原图路径

    let imageFile = directory.appendingPathComponent("original.png")
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageFile)
    let imageItem = ClipboardItem(kind: .image, preview: "图片", imagePath: imageFile.path,
                                  imageWidth: 1280, imageHeight: 720,
                                  contentHash: "preview-image", ocrText: "识别出来的文字")
    let imageTarget = try! ClipboardPreviewBuilder.target(for: imageItem, directory: directory)
    assertEqual(imageTarget.content, .image(imageFile), "图片条目给原图路径")
    assertEqual(imageTarget.title, "图片 1280×720", "图片标题带尺寸")
    assertEqual(imageTarget.ocrText, "识别出来的文字", "识别文字随预览项带出")
    assertEqual(imageTarget.characterCount, nil, "图片不给字符数")

    // 原图缺失 → imageMissing
    let missing = ClipboardItem(kind: .image, preview: "图片", imagePath: "/tmp/definitely-missing.png",
                                contentHash: "preview-image-missing")
    do {
        _ = try ClipboardPreviewBuilder.target(for: missing, directory: directory)
        assertEqual("未抛错", "应抛 imageMissing", "原图缺失必须报错")
    } catch {
        assertEqual(error as? ClipboardPreviewError, .imageMissing, "原图缺失抛 imageMissing")
    }

    // 无识别结果时 ocrText 为 nil（没有识别文字与识别出空串等价）
    let noOCR = ClipboardItem(kind: .image, preview: "图片", imagePath: imageFile.path,
                              contentHash: "preview-image-no-ocr", ocrText: "  ")
    assertEqual(try! ClipboardPreviewBuilder.target(for: noOCR, directory: directory).ocrText, nil,
                "空白识别结果不上报")

    // MARK: 文件条目 → 存在的那个 URL

    let existing = directory.appendingPathComponent("设计稿.sketch")
    try? Data([0x01]).write(to: existing)
    let fileItem = ClipboardItem(kind: .file,
                                 text: "/tmp/definitely-missing-1.sketch\n\(existing.path)",
                                 preview: "设计稿", contentHash: "preview-file")
    let fileTarget = try! ClipboardPreviewBuilder.target(for: fileItem, directory: directory)
    assertEqual(fileTarget.content, .file(existing), "文件条目取第一个真实存在的路径")
    assertContains(fileTarget.title, "设计稿.sketch", "文件标题带文件名")

    // 全部不存在 → fileMissing
    let goneFiles = ClipboardItem(kind: .file, text: "/tmp/definitely-missing-a\n/tmp/definitely-missing-b",
                                  preview: "文件", contentHash: "preview-file-gone")
    do {
        _ = try ClipboardPreviewBuilder.target(for: goneFiles, directory: directory)
        assertEqual("未抛错", "应抛 fileMissing", "文件全丢必须报错")
    } catch {
        assertEqual(error as? ClipboardPreviewError, .fileMissing, "文件全丢抛 fileMissing")
    }

    // MARK: 临时目录清理

    assertEqual(fileManager.fileExists(atPath: directory.path), true, "清理前目录存在")
    assertEqual(ClipboardPreviewBuilder.removeTemporaryDirectory(directory), true, "首次清理成功")
    assertEqual(fileManager.fileExists(atPath: directory.path), false, "清理后目录已删除")
    assertEqual(ClipboardPreviewBuilder.removeTemporaryDirectory(directory), true, "目录不存在时清理仍成功（幂等）")

    // MARK: 默认目录口径

    assertEqual(ClipboardPreviewBuilder.defaultTemporaryDirectory().lastPathComponent,
                ClipboardPreviewBuilder.temporaryDirectoryName, "默认目录名为固定常量")
    assertEqual(ClipboardPreviewBuilder.defaultTemporaryDirectory().path.hasPrefix(NSTemporaryDirectory()),
                true, "默认目录落在系统临时目录下")

    print("✅ clipboard preview target tests passed")
}
