import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片拖拽载荷（阈值 / 文本 / 图片 / 文件 / 多选）

/// 拖到其他 App 的载荷口径守卫
///
/// 钉住四件事：
/// 1. 起拖阈值 —— 位移不到阈值绝不起拖（单击行为不变的硬约束）；
/// 2. 文本条目 —— 单个拖拽项，写 .string；
/// 3. 图片 / 文件条目 —— 写 .fileURL（图片另有 .tiff 表示）；
/// 4. 多选 —— 图片 / 文件各成一个拖拽项，文本合并成一条多行文本。
func runClipboardDragPayloadTests() {
    print("🧪 Testing clipboard drag payloads...")

    // MARK: 起拖阈值

    let anchor = CGPoint(x: 100, y: 100)
    assertEqual(ClipboardDragPayloadBuilder.dragThreshold, 4, "起拖阈值是 4pt")
    assertEqual(ClipboardDragPayloadBuilder.shouldBeginDrag(from: anchor, to: CGPoint(x: 100, y: 100)),
                false, "原地不动不起拖")
    assertEqual(ClipboardDragPayloadBuilder.shouldBeginDrag(from: anchor, to: CGPoint(x: 102, y: 100)),
                false, "位移 2pt 仍在单击范围")
    assertEqual(ClipboardDragPayloadBuilder.shouldBeginDrag(from: anchor, to: CGPoint(x: 104, y: 100)),
                true, "位移达 4pt 起拖")
    assertEqual(ClipboardDragPayloadBuilder.shouldBeginDrag(from: anchor, to: CGPoint(x: 96, y: 100)),
                true, "反方向位移同样按距离判定")
    assertEqual(ClipboardDragPayloadBuilder.shouldBeginDrag(from: anchor, to: CGPoint(x: 103, y: 103)),
                true, "斜向位移按直线距离判定")

    // MARK: 文本条目

    let text = ClipboardItem(kind: .text, text: "你好，剪贴板", preview: "你好，剪贴板",
                             contentHash: "drag-text")
    let textPayloads = ClipboardDragPayloadBuilder.payloads(for: [text])
    assertEqual(textPayloads.count, 1, "单条文本只产生一个拖拽项")
    assertEqual(textPayloads.first?.representations.count, 1, "文本只写一种表示")
    assertEqual(textPayloads.first?.representations.first?.type,
                ClipboardDragPayloadBuilder.PasteboardType.string, "文本写 .string")
    assertEqual(textPayloads.first?.representations.first?.content, .string("你好，剪贴板"),
                "文本载荷就是正文")

    let literalText = ClipboardItem(kind: .text, text: "看得见 (v2)", preview: "脱字符",
                                     contentHash: "drag-literal")
    assertEqual(ClipboardDragPayloadBuilder.payloads(for: [literalText]).first?.representations.first?.content,
                .string("看得见 (v2)"), "正文按字面写入，不做转义")

    let emptyText = ClipboardItem(kind: .text, text: "", preview: "", contentHash: "drag-empty")
    assertEqual(ClipboardDragPayloadBuilder.payloads(for: [emptyText]).isEmpty, true,
                "空文本不产生空拖拽项")

    // MARK: 图片条目

    let image = ClipboardItem(kind: .image, preview: "图片 100×50", imagePath: "/tmp/drag-image.png",
                              imageWidth: 100, imageHeight: 50, contentHash: "drag-image")
    let imagePayloads = ClipboardDragPayloadBuilder.payloads(
        for: [image],
        imageData: { _ in Data([0x49, 0x49]) },
        fileExists: { $0 == "/tmp/drag-image.png" })
    assertEqual(imagePayloads.count, 1, "单张图片产生一个拖拽项")
    assertEqual(imagePayloads.first?.representations.map(\.type),
                [ClipboardDragPayloadBuilder.PasteboardType.fileURL,
                 ClipboardDragPayloadBuilder.PasteboardType.tiff],
                "图片同时写 .fileURL 与 .tiff 双表示")
    assertEqual(imagePayloads.first?.representations.first?.content, .fileURL("/tmp/drag-image.png"),
                "图片首选表示是原图路径")

    let noData = ClipboardDragPayloadBuilder.payloads(
        for: [image], imageData: { _ in nil }, fileExists: { _ in true })
    assertEqual(noData.first?.representations.map(\.type),
                [ClipboardDragPayloadBuilder.PasteboardType.fileURL],
                "TIFF 拿不到时保留文件 URL 退路")

    let missingImage = ClipboardDragPayloadBuilder.payloads(
        for: [image], imageData: { _ in Data([0x01]) }, fileExists: { _ in false })
    assertEqual(missingImage.isEmpty, true, "原图不在磁盘上时不产生空载荷")

    // MARK: 文件条目

    let file = ClipboardItem(kind: .file,
                             text: "/tmp/drag-a.txt\n/tmp/drag-b.txt\n",
                             preview: "/tmp/drag-a.txt",
                             contentHash: "drag-file")
    let filePayloads = ClipboardDragPayloadBuilder.payloads(
        for: [file], fileExists: { $0.hasPrefix("/tmp/drag-") })
    assertEqual(filePayloads.count, 2, "两条路径各产生一个拖拽项")
    assertEqual(filePayloads.first?.representations.map(\.type),
                [ClipboardDragPayloadBuilder.PasteboardType.fileURL,
                 ClipboardDragPayloadBuilder.PasteboardType.string],
                "文件写 .fileURL 并附带路径文本")
    assertEqual(filePayloads.first?.representations.first?.content, .fileURL("/tmp/drag-a.txt"),
                "文件载荷取真实路径")
    let oneMissing = ClipboardDragPayloadBuilder.payloads(
        for: [file], fileExists: { $0 == "/tmp/drag-b.txt" })
    assertEqual(oneMissing.count, 1, "不存在的路径被过滤，只拖剩下的")

    // MARK: 多选

    let secondImage = ClipboardItem(kind: .image, preview: "图片 20×20", imagePath: "/tmp/drag-image-2.png",
                                    contentHash: "drag-image-2")
    let secondText = ClipboardItem(kind: .text, text: "第二条", preview: "第二条",
                                   contentHash: "drag-text-2")
    let mixedPayloads = ClipboardDragPayloadBuilder.payloads(
        for: [secondText, image, secondImage, text],
        imageData: { _ in Data([0x4D, 0x4D]) },
        fileExists: { $0.hasPrefix("/tmp/drag-") })
    assertEqual(mixedPayloads.count, 3, "多选：两张图片各一项 + 文本合并一项")
    assertEqual(mixedPayloads.last?.representations.first?.content, .string("第二条\n你好，剪贴板"),
                "多选文本按选中顺序合并成多行一条")

    let secondFile = ClipboardItem(kind: .file, text: "/tmp/drag-c.txt", preview: "/tmp/drag-c.txt",
                                   contentHash: "drag-file-2")
    let mixedFiles = ClipboardDragPayloadBuilder.payloads(
        for: [file, secondFile], fileExists: { $0.hasPrefix("/tmp/drag-") })
    assertEqual(mixedFiles.count, 3, "多选文件逐条展开（a / b / c 三项）")

    // MARK: 携带条目

    let outside = ClipboardItem(kind: .text, text: "未选中", preview: "未选中", contentHash: "drag-outside")
    assertEqual(ClipboardDragPayloadBuilder.carriedItems(selection: [text, image], current: text).count, 2,
                "本条在选中集合里就带整组")
    assertEqual(ClipboardDragPayloadBuilder.carriedItems(selection: [text, image], current: outside)
        .map(\.id), [outside.id], "本条不在集合里时只带本条")

    print("✅ Clipboard drag payloads (threshold / text / image / file / multi-select) works")
}
