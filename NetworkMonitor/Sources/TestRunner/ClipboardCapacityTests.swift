import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板容量上限（口径纯函数 + 超限清理）

/// 覆盖「最大容量」需求的纯逻辑两半（零 IO）：
/// 1. 容量口径（`ClipboardCapacityUsage` 纯函数）：文本 / 图片 / 混合 / 缩略图不计入 / 空库；
/// 2. 超限选择：删最旧直到达标 / 刚好等于上限不删 / 上限 0 = 不限 / 收藏豁免；
/// 3. 展示文案与输入解析（「x / 上限 y」、非法输入拦截）。
///
/// 真实链路（内存库 + 临时目录里的真删文件、与按条数并存）在
/// `ClipboardCapacityPruneTests.swift`，两边共用同一个入口。
func runClipboardCapacityTests() {
    print("🧪 Testing Clipboard capacity limit...")
    runCapacityByteCountTests()
    runCapacityOverflowSelectionTests()
    runCapacityDisplayAndInputTests()
    print("✅ Clipboard 容量上限（口径 / 超限选择 / 展示与输入）works")
    // 清理编排（先条数后容量的顺序断言）与真实链路（内存库 + 临时目录）各自成文件，
    // 由这里一并驱动：main.swift 已贴着单文件上限，容量这一族只占入口一行
    runClipboardLimitPrunerTests()
    runClipboardCapacityPruneTests()
}

// MARK: - 夹具

/// 固定大小的假图片字节表：路径 → 字节（不碰真实文件系统）
private func capacityFakeImages(_ table: [String: UInt64]) -> (String) -> UInt64 {
    { table[$0] ?? 0 }
}

private func capacityItem(kind: ClipboardItemKind, text: String? = nil, imagePath: String? = nil,
                          createdAt: Date, pinned: Bool = false, hash: String) -> ClipboardItem {
    ClipboardItem(kind: kind, text: text, imagePath: imagePath, contentHash: hash,
                  isPinned: pinned, createdAt: createdAt)
}

// MARK: - 1) 容量口径

private func runCapacityByteCountTests() {
    // 1.1 纯文本：按 UTF-8 字节算（中文 3 字节，不能被字符数糊弄）
    let textItem = capacityItem(kind: .text, text: "abc中文", createdAt: Date(), hash: "t1")
    assertEqual(ClipboardCapacityUsage.byteCount(of: textItem,
                                                 imageByteCount: capacityFakeImages([:])),
                UInt64(3 + 6), "文本按 UTF-8 字节统计")

    // 1.2 只有图片：取注入的落盘字节；读不到文件（路径不在表里）按 0 计
    let imageItem = capacityItem(kind: .image, imagePath: "/tmp/a.png", createdAt: Date(), hash: "i1")
    assertEqual(ClipboardCapacityUsage.byteCount(of: imageItem,
                                                 imageByteCount: capacityFakeImages(["/tmp/a.png": 4_096])),
                UInt64(4_096), "图片按原图文件字节统计")
    assertEqual(ClipboardCapacityUsage.byteCount(of: imageItem,
                                                 imageByteCount: capacityFakeImages([:])),
                UInt64(0), "图片文件读不到时按 0 计（不炸）")
    let noPathImage = capacityItem(kind: .image, createdAt: Date(), hash: "i2")
    assertEqual(ClipboardCapacityUsage.byteCount(of: noPathImage,
                                                 imageByteCount: capacityFakeImages(["/tmp/a.png": 4_096])),
                UInt64(0), "图片条目没有路径时按 0 计")

    // 1.3 图文混合：总和 = 文本字节 + 图片字节；缩略图不在条目里，天然不计入
    //     （缩略图是原图的派生物，随原图回收；计入会让统计随缓存重建抖动）
    let mixed = [textItem, imageItem]
    let total = ClipboardCapacityUsage.totalBytes(of: mixed,
                                                  imageByteCount: capacityFakeImages(["/tmp/a.png": 4_096]))
    assertEqual(total, UInt64(9 + 4_096), "图文混合总量 = 文本 + 图片原图")
    let counts = ClipboardCapacityUsage.byteCounts(of: mixed,
                                                   imageByteCount: capacityFakeImages(["/tmp/a.png": 4_096]))
    assertEqual(counts[textItem.id], UInt64(9), "逐条字节：文本")
    assertEqual(counts[imageItem.id], UInt64(4_096), "逐条字节：图片")

    // 1.4 空库
    assertEqual(ClipboardCapacityUsage.totalBytes(of: [], imageByteCount: capacityFakeImages([:])), UInt64(0),
                "空库总量为 0")
    assertEqual(ClipboardCapacityUsage.byteCounts(of: [], imageByteCount: capacityFakeImages([:])).isEmpty,
                true, "空库逐条字节为空")

    // 1.5 真实文件字节：文件不存在 / 空路径都不报错
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipboard-capacity-bytes", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("img.png")
    try? Data(repeating: 3, count: 2_048).write(to: file)
    assertEqual(ClipboardCapacityUsage.fileByteCount(atPath: file.path), UInt64(2_048), "真实文件字节可读")
    assertEqual(ClipboardCapacityUsage.fileByteCount(atPath: directory.appendingPathComponent("nope.png").path),
                UInt64(0), "文件不存在时字节为 0")
    assertEqual(ClipboardCapacityUsage.fileByteCount(atPath: ""), UInt64(0), "空路径字节为 0")
    try? FileManager.default.removeItem(at: directory)

    print("✅ Clipboard 容量口径（文本 / 图片 / 混合 / 缩略图不计入 / 空库 / 真实文件）works")
}

// MARK: - 2) 超限选择

private func runCapacityOverflowSelectionTests() {
    let base = Date(timeIntervalSince1970: 1_000)
    // 三条各 40 字节的文本，按时间先后排列（oldest → newest）
    let oldest = capacityItem(kind: .text, text: String(repeating: "a", count: 40),
                              createdAt: base, hash: "o")
    let middle = capacityItem(kind: .text, text: String(repeating: "b", count: 40),
                              createdAt: base.addingTimeInterval(1), hash: "m")
    let newest = capacityItem(kind: .text, text: String(repeating: "c", count: 40),
                              createdAt: base.addingTimeInterval(2), hash: "n")
    let items = [newest, middle, oldest]  // 故意乱序：选择逻辑要自己按时间排
    let counts = ClipboardCapacityUsage.byteCounts(of: items, imageByteCount: capacityFakeImages([:]))

    // 2.1 超限 → 从最旧开始删到回到上限以内
    assertEqual(ClipboardCapacityUsage.isOverLimit(totalBytes: 120, maxBytes: 100), true, "120 > 100 算超限")
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: items, byteCounts: counts, maxBytes: 100),
                [oldest.id], "120 字节上限 100：删最旧一条即可达标")
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: items, byteCounts: counts, maxBytes: 50),
                [oldest.id, middle.id], "上限 50：删两条（最旧→次新）")
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: items, byteCounts: counts, maxBytes: 10).count, 3,
                "上限 10：三条全删")

    // 2.2 刚好等于上限不删
    assertEqual(ClipboardCapacityUsage.isOverLimit(totalBytes: 100, maxBytes: 100), false,
                "等于上限不算超限")
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: items, byteCounts: counts, maxBytes: 120).isEmpty,
                true, "刚好等于上限不删任何条目")

    // 2.3 上限 0 = 不限
    assertEqual(ClipboardCapacityUsage.isOverLimit(totalBytes: 9_999_999, maxBytes: 0), false,
                "上限 0 表示不限，永不超限")
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: items, byteCounts: counts, maxBytes: 0).isEmpty,
                true, "上限 0 时不删任何条目")

    // 2.4 豁免项（收藏 / 板内条目）计入总量但不被删
    let pinned = capacityItem(kind: .text, text: String(repeating: "p", count: 90),
                              createdAt: base, pinned: true, hash: "p")
    let ordinary = capacityItem(kind: .text, text: String(repeating: "o", count: 90),
                                createdAt: base.addingTimeInterval(1), hash: "q")
    let withPinned = [pinned, ordinary]
    let pinnedCounts = ClipboardCapacityUsage.byteCounts(of: withPinned, imageByteCount: capacityFakeImages([:]))
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: withPinned, byteCounts: pinnedCounts, maxBytes: 100),
                [ordinary.id], "收藏项不被删，只删普通条目")
    assertEqual(ClipboardCapacityUsage.overflowIDs(of: [pinned], byteCounts: pinnedCounts, maxBytes: 10).isEmpty,
                true, "只剩收藏项超限时不越权删除（宁可超一点也不动收藏）")

    print("✅ Clipboard 超限选择（删最旧 / 等于上限不删 / 0 = 不限 / 收藏豁免）works")
}

// MARK: - 3) 展示文案与输入解析

private func runCapacityDisplayAndInputTests() {
    // 3.1 「x / 上限 y」
    assertEqual(ClipboardCapacityUsage.displayText(usedBytes: 0, limitBytes: 100 * 1024 * 1024),
                "0 B / 上限 100.0 MB", "占用与上限同屏显示")
    assertEqual(ClipboardCapacityUsage.displayText(usedBytes: 52_428_800, limitBytes: 100 * 1024 * 1024),
                "50.0 MB / 上限 100.0 MB", "占用按 1024 进位换算")
    assertEqual(ClipboardCapacityUsage.displayText(usedBytes: 2_048, limitBytes: 0),
                "2.0 KB / 不限", "上限 0 显示「不限」")

    // 3.2 输入解析：整数通过，负数 / 非数字 / 空串拦住，0 合法
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: "100"), .success(104_857_600), "100 → 字节")
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: " 0 "), .success(0), "0 = 不限且允许首尾空白")
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: ""), .failure(.notNumber), "空串拦住")
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: "abc"), .failure(.notNumber), "字母拦住")
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: "1.5"), .failure(.notNumber), "小数拦住")
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: "-5"), .failure(.negative), "负数拦住")
    assertEqual(ClipboardCapacityUsage.parsedMegabytes(from: "99999999999999999999"),
                .failure(.notNumber), "溢出（超大数字）拦住而不是静默截断")
    assertEqual(ClipboardCapacityUsage.InputError.notNumber.message, "请输入整数 MB（0 = 不限）",
                "非法输入提示文案")
    assertEqual(ClipboardCapacityUsage.InputError.negative.message, "不能是负数（0 = 不限）",
                "负数输入提示文案")

    print("✅ Clipboard 容量展示与输入（x / 上限 y / 不限 / 非法输入拦截）works")
}

