import Foundation
import NetworkMonitorCore

// MARK: - 图片落盘

/// 图片落盘工具 — 像素守卫 + ImageIO 缩略图 + 真实扩展名
///
/// 落盘约定（内容哈希命名，原图与缩略图成对）：
/// - 原图：~/Library/Application Support/macMonitor/clipboard/images/<hash>.<真实扩展名>
/// - 缩略图：<hash>_thumb.png（最长边 320，ImageIO 降采样生成）
///
/// 三条硬约束：
/// 1. 落盘前必须过 `ClipboardImagePolicy` 像素守卫（12000×12000 这类像素炸弹只记录占位，不落盘）
/// 2. 禁止 NSImage + tiffRepresentation（会把整张位图展开，实测峰值 2764MB）
/// 3. 扩展名取自字节真实类型，不再统一写 .png（旧缺陷：TIFF 字节装进 .png 文件名）
enum ClipboardImageStore {

    /// 落盘结果
    struct Stored: Equatable, Sendable {
        /// 原图路径
        let path: String
        /// 像素宽
        let width: Int
        /// 像素高
        let height: Int
    }

    /// 落盘结局
    enum Outcome: Equatable, Sendable {
        /// 已落盘并生成缩略图
        case stored(Stored)
        /// 像素守卫拒绝：不落盘、不缓存，调用方走占位降级
        case rejected(ClipboardImageRejection)
    }

    /// 图片目录
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("macMonitor/clipboard/images", isDirectory: true)
    }

    /// 缩略图路径（卡片视图懒加载用）
    static func thumbnailURL(for contentHash: String) -> URL {
        directory.appendingPathComponent("\(contentHash)_thumb.png")
    }

    /// 原图路径（真实扩展名；仅落盘时使用，读取一律走 DB 里的 imagePath）
    static func originalURL(for contentHash: String, fileExtension: String) -> URL {
        directory.appendingPathComponent("\(contentHash).\(fileExtension)")
    }

    // MARK: 落盘

    /// 像素守卫 + 原图落盘 + 缩略图生成
    /// - Parameters:
    ///   - data: 被选中表示的原始字节（PNG 或 TIFF）
    ///   - contentHash: 内容哈希（命名用）
    ///   - logger: 日志
    /// - Returns: 已落盘（含尺寸）或像素守卫拒绝；IO 失败返回 nil
    static func store(data: Data, contentHash: String, logger: LoggingService) -> Outcome? {
        // 读不出尺寸 = 字节本身坏了（不是「太大」），按旧行为整条跳过，不产生占位记录
        guard let size = ClipboardImageDecoder.pixelSize(of: data) else {
            logger.debug("剪贴板图片无法读取尺寸，跳过落库：\(contentHash.prefix(8))")
            return nil
        }
        if let rejection = ClipboardImagePolicy.rejection(width: size.width, height: size.height) {
            logger.debug("剪贴板图片未落盘：\(rejection.logDescription)")
            return .rejected(rejection)
        }
        let fileExtension = ClipboardImageDecoder.fileExtension(of: data) ?? "png"
        let directory = Self.directory
        let fileURL = originalURL(for: contentHash, fileExtension: fileExtension)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("剪贴板图片落盘失败：\(error.localizedDescription)")
            return nil
        }
        // 落盘期不清理同哈希的旧版 <hash>.png：此时记录刚写入、旧副本可能仍被历史记录引用，
        // 删掉会让老记录指向不存在的路径。真正的清理放在记录被删除之后（见 remove / sweepOrphans）。
        writeThumbnail(data: data, to: thumbnailURL(for: contentHash), logger: logger)
        return .stored(Stored(path: fileURL.path, width: size.width, height: size.height))
    }

    // MARK: 缩略图

    /// 生成并写入缩略图（ImageIO 内部降采样，不展开原图）
    static func writeThumbnail(data: Data, to url: URL, logger: LoggingService) {
        guard let thumbnail = ClipboardImageDecoder.thumbnail(from: data),
              let png = ClipboardImageDecoder.pngData(from: thumbnail) else {
            logger.warning("剪贴板缩略图生成失败，卡片将降级为占位符号")
            return
        }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            logger.warning("剪贴板缩略图写入失败：\(error.localizedDescription)")
        }
    }

    // MARK: 回收

    /// 回收单条被删图片的落盘文件（原图任意扩展名副本 + 缩略图）
    /// - Parameters:
    ///   - imagePath: DB 里记录的精确路径（扩展名可能与该哈希现有文件不一致，由判定层负责对上）
    ///   - contentHash: 内容哈希前缀（覆盖同哈希换扩展名遗留的旧副本）
    ///   - logger: 日志（路径先过 LogRedaction）
    /// - Returns: 实际删除的文件数
    @discardableResult
    static func remove(imagePath: String?, contentHash: String, logger: LoggingService) -> Int {
        guard let fileNames = ClipboardImageSweeper.fileNames(in: directory) else { return 0 }
        let doomed = ClipboardImageSweepPlan.reclaimableFileNames(
            fileNames: fileNames,
            doomedImagePaths: imagePath.map { Set([$0]) } ?? [],
            doomedContentHashes: contentHash.isEmpty ? [] : Set([contentHash])
        )
        return ClipboardImageSweeper.remove(fileNames: doomed, in: directory, logger: logger)
    }

    /// 启动后一次孤儿清扫：目录内没有存活记录引用的文件全部删除
    /// - Parameters:
    ///   - knownImagePaths: 全量 DB 记录的 image_path
    ///   - knownContentHashes: 全量 DB 记录的 content_hash
    /// - Returns: 实际删除的文件数；目录不存在时返回 0（不报错）
    @discardableResult
    static func sweepOrphans(knownImagePaths: Set<String>, knownContentHashes: Set<String>,
                             logger: LoggingService) -> Int {
        guard let fileNames = ClipboardImageSweeper.fileNames(in: directory), !fileNames.isEmpty else { return 0 }
        let orphans = ClipboardImageSweepPlan.orphanFileNames(fileNames: fileNames,
                                                              keptImagePaths: knownImagePaths,
                                                              keptContentHashes: knownContentHashes)
        return ClipboardImageSweeper.remove(fileNames: orphans, in: directory, logger: logger)
    }

    /// 从原图补生成缩略图（缩略图文件缺失时懒加载；ImageIO 降采样，代价与缩略图尺寸成正比）
    /// - Returns: 是否生成成功
    static func regenerateThumbnail(contentHash: String, imagePath: String, logger: LoggingService) -> Bool {
        guard let size = ClipboardImageDecoder.pixelSize(ofFileAt: imagePath),
              ClipboardImagePolicy.isAllowed(width: size.width, height: size.height) else {
            logger.debug("补生成缩略图被像素守卫拒绝：\(contentHash.prefix(8))")
            return false
        }
        guard let thumbnail = ClipboardImageDecoder.thumbnail(fromFileAt: imagePath),
              let png = ClipboardImageDecoder.pngData(from: thumbnail) else { return false }
        let url = thumbnailURL(for: contentHash)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return true
        } catch {
            logger.warning("剪贴板缩略图补写失败：\(error.localizedDescription)")
            return false
        }
    }
}
