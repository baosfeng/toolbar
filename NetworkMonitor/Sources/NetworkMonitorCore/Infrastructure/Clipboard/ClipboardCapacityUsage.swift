import Foundation

// MARK: - 剪贴板容量口径（纯函数）

/// 剪贴板历史「总占用字节」的计算与超限选择 —— 无 AppKit、无数据库依赖，全部可单测
///
/// 口径（与设置页「存储」卡、超限清理共用同一份实现）：
/// - 文本 / RTF / 文件条目：只算正文 `text` 的 **UTF-8 字节**；
/// - 图片条目：只算**原图文件的实际字节**（由调用方注入的 `imageByteCount` 读取落盘大小）；
/// - **缩略图不计入**：缩略图是原图的派生物，随原图一起回收（见 `ClipboardImageSweepPlan`），
///   若计入会让统计随缩略图缓存生成 / 重建而抖动，用户看到的「占用」就会莫名变大变小；
/// - 摘要 `preview` 与 OCR 结果同样是派生物，同样不计入（同一口径，避免双重计价）。
///
/// 上限语义：`maxBytes == 0` 表示不限，负值同样按不限处理（偏好层已归一化，这里再兜一层）。
public enum ClipboardCapacityUsage {

    /// 「不限」的哨兵值（偏好里存 0）
    public static let unlimited: UInt64 = 0

    // MARK: - 单条字节

    /// 单条条目的字节数（正文 UTF-8 字节；图片取注入的落盘大小）
    /// - Parameters:
    ///   - item: 条目
    ///   - imageByteCount: 原图路径 → 文件字节；读不到（文件已删 / 权限）时返回 0
    public static func byteCount(of item: ClipboardItem, imageByteCount: (String) -> UInt64) -> UInt64 {
        guard item.isImage else { return UInt64(item.text?.utf8.count ?? 0) }
        guard let path = item.imagePath, !path.isEmpty else { return 0 }
        return imageByteCount(path)
    }

    /// 全量条目的逐条字节（id → 字节）
    public static func byteCounts(of items: [ClipboardItem],
                                  imageByteCount: (String) -> UInt64) -> [UUID: UInt64] {
        var result: [UUID: UInt64] = [:]
        result.reserveCapacity(items.count)
        for item in items {
            result[item.id] = byteCount(of: item, imageByteCount: imageByteCount)
        }
        return result
    }

    /// 全量条目的总占用（字节）
    public static func totalBytes(of items: [ClipboardItem],
                                  imageByteCount: (String) -> UInt64) -> UInt64 {
        items.reduce(UInt64(0)) { $0 + byteCount(of: $1, imageByteCount: imageByteCount) }
    }

    // MARK: - 超限选择

    /// 是否超限（`maxBytes` 为 0 恒不超限）
    public static func isOverLimit(totalBytes: UInt64, maxBytes: UInt64) -> Bool {
        maxBytes != unlimited && totalBytes > maxBytes
    }

    /// 超限时该删的条目 id —— **从最旧开始**，删到达标为止
    ///
    /// 豁免口径与按条数清理完全一致：收藏项（`isPinned`）与板内条目（`boardID != nil`）不参与删除，
    /// 但也**计入**总量（它们确实占着磁盘，只是不能为了腾空间而牺牲）。
    /// 因此豁免项自身就可能超过上限：这时只会把可清理项删到一个不剩，不会越权删收藏。
    /// - Returns: 待删 id（按最旧→最新顺序）；不超限或 `maxBytes == 0` 时为空
    public static func overflowIDs(of items: [ClipboardItem],
                                   byteCounts: [UUID: UInt64],
                                   maxBytes: UInt64) -> [UUID] {
        guard maxBytes != unlimited else { return [] }
        var total = items.reduce(UInt64(0)) { $0 + (byteCounts[$1.id] ?? 0) }
        guard total > maxBytes else { return [] }

        // 可清理项按创建时间升序（最旧在前）；同一时刻用 id 兜底，保证结果确定
        let candidates = items
            .filter { isPrunable($0) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var doomed: [UUID] = []
        for item in candidates {
            guard total > maxBytes else { break }
            let bytes = byteCounts[item.id] ?? 0
            doomed.append(item.id)
            total = total > bytes ? total - bytes : 0
        }
        return doomed
    }

    /// 可被自动清理的条目（收藏项与板内条目豁免，口径与按条数清理一致）
    public static func isPrunable(_ item: ClipboardItem) -> Bool {
        !item.isPinned && item.boardID == nil
    }

    // MARK: - 展示文案

    /// 设置页「占用」行文案：「x MB / 上限 y MB」；不限时写成「x MB / 不限」
    ///
    /// - Parameters:
    ///   - usedBytes: 当前总占用（条目正文 + 图片原图）
    ///   - limitBytes: 上限字节；0 = 不限
    public static func displayText(usedBytes: UInt64, limitBytes: UInt64) -> String {
        let used = SystemDetailFormatting.byteCountText(usedBytes)
        guard limitBytes != unlimited else { return used + " / 不限" }
        return used + " / 上限 " + SystemDetailFormatting.byteCountText(limitBytes)
    }

    // MARK: - 输入解析

    /// 「最大容量」输入框的解析失败原因（视图只负责把 message 显示成副标题）
    public enum InputError: Error, Equatable, Sendable {
        /// 不是整数（空串 / 小数 / 字母 / 夹杂空格与符号）
        case notNumber
        /// 负数
        case negative

        /// 给用户看的说明（中文，直接当行副标题）
        public var message: String {
            switch self {
            case .notNumber: return "请输入整数 MB（0 = 不限）"
            case .negative: return "不能是负数（0 = 不限）"
            }
        }
    }

    /// 把输入框里的 MB 文本解析成字节上限
    ///
    /// 规则：允许首尾空白；只接受非负整数；空串、小数、字母、负号之外的符号一律按「不是数字」拒绝。
    /// 结果按 1024 × 1024 换算成字节，故界面上填 100 就是 100 MB。
    /// - Parameters:
    ///   - text: 输入框文本（MB）
    ///   - bytesPerMegabyte: 换算基数（默认 1 MB = 1048576 字节）
    public static func parsedMegabytes(from text: String,
                                       bytesPerMegabyte: UInt64 = 1024 * 1024) -> Result<UInt64, InputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.notNumber) }
        if trimmed.hasPrefix("-") { return .failure(.negative) }
        guard let megabytes = UInt64(trimmed) else { return .failure(.notNumber) }
        let (bytes, overflow) = megabytes.multipliedReportingOverflow(by: bytesPerMegabyte)
        // 溢出按「不值当的极大值」拦住，不静默截断成一个小数字
        return overflow ? .failure(.notNumber) : .success(bytes)
    }

    // MARK: - 文件字节读取

    /// 读取文件字节（`imageByteCount` 的生产实现）
    ///
    /// 文件不存在（已被回收）/ 不可读时返回 0，不抛错：容量统计绝不能因为一个坏文件而失败。
    public static func fileByteCount(atPath path: String) -> UInt64 {
        guard !path.isEmpty else { return 0 }
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size > 0 else { return 0 }
        return UInt64(size)
    }
}
