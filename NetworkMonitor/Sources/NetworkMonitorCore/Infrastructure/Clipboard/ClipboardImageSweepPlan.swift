import Foundation

// MARK: - 剪贴板图片回收判定（纯函数）

/// 剪贴板图片落盘文件的回收判定 —— 无 AppKit 依赖、不触文件系统，便于测试
///
/// 文件名约定（与 `ClipboardImageStore` 落盘一致）：
/// - 原图：`<contentHash>.<真实扩展名>`
/// - 缩略图：`<contentHash>_thumb.png`
/// - 同哈希换扩展名时还可能残留 `<contentHash>.<旧扩展名>`（见 store 内的保留注释）
///
/// 两套判定共用同一套「文件名 ↔ 内容哈希」解析，避免删除路径与启动清扫各写一套口径：
/// 1. `reclaimableFileNames(...)`：某次删除操作已被删条目对应的文件（删除 / 清空 / 超限清理）
/// 2. `orphanFileNames(...)`：目录内无任何存活记录引用的文件（启动后一次清扫）
public enum ClipboardImageSweepPlan {

    /// 缩略图文件名后缀
    public static let thumbnailSuffix = "_thumb.png"

    // MARK: - 文件名解析

    /// 路径末尾的文件名（DB 里的 image_path 是全路径，目录列举给的是纯文件名）
    public static func baseName(ofPath path: String) -> String {
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// 从文件名取出内容哈希前缀；不符合落盘约定（无扩展名、只有后缀、空主干）返回 nil
    public static func hashPrefix(of fileName: String) -> String? {
        if fileName.hasSuffix(thumbnailSuffix) {
            let hash = String(fileName.dropLast(thumbnailSuffix.count))
            return hash.isEmpty ? nil : hash
        }
        let ext = (fileName as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        let stem = String(fileName.dropLast(ext.count + 1))
        return stem.isEmpty ? nil : stem
    }

    /// 文件名是否属于给定内容哈希（任意扩展名的原图副本 + 缩略图）
    public static func belongsToHash(_ fileName: String, _ contentHashes: Set<String>) -> Bool {
        guard let hash = hashPrefix(of: fileName) else { return false }
        return contentHashes.contains(hash)
    }

    // MARK: - 判定

    /// 被删条目关联的文件名（DB 精确路径 + 同哈希任意扩展名副本 + 缩略图）
    ///
    /// - Parameters:
    ///   - fileNames: 目录内已有文件名（纯文件名）
    ///   - doomedImagePaths: 被删条目的 `imagePath`（全路径；扩展名不一致也能命中）
    ///   - doomedContentHashes: 被删条目的 `contentHash`
    /// - Returns: 待删文件名；两个集合都为空时返回空数组（调用方据此零 IO）
    public static func reclaimableFileNames(fileNames: [String],
                                            doomedImagePaths: Set<String>,
                                            doomedContentHashes: Set<String>) -> [String] {
        let doomedBaseNames = Set(doomedImagePaths.map(baseName(ofPath:)).filter { !$0.isEmpty })
        guard !doomedBaseNames.isEmpty || !doomedContentHashes.isEmpty else { return [] }
        return fileNames.filter { fileName in
            doomedBaseNames.contains(fileName) || belongsToHash(fileName, doomedContentHashes)
        }
    }

    /// 无任何存活记录引用的文件名（孤儿清扫用）
    ///
    /// 判据：文件名 stem 命中存活条目的 `image_path` 或 `content_hash` 即保留；
    /// 非落盘约定命名的文件（不含哈希前缀）一律视为无引用。
    public static func orphanFileNames(fileNames: [String],
                                       keptImagePaths: Set<String>,
                                       keptContentHashes: Set<String>) -> [String] {
        let keptBaseNames = Set(keptImagePaths.map(baseName(ofPath:)).filter { !$0.isEmpty })
        return fileNames.filter { fileName in
            if keptBaseNames.contains(fileName) { return false }
            guard let hash = hashPrefix(of: fileName) else { return true }
            return !keptContentHashes.contains(hash)
        }
    }
}

// MARK: - 文件删除执行器（唯一 IO 触点）

/// 目录列举与删除 —— 判定全部在 `ClipboardImageSweepPlan`，本类型只做 FileManager 调用
///
/// 放在 Core 的原因：TestRunner 依赖 Core 而不依赖 App target，
/// 删文件的行为要能跑「临时目录 + 真 IO」的断言，而不是在测试里复刻一套删除实现。
/// App 层 `ClipboardImageGC` 只负责拼装「被删 / 存活」集合并记日志。
public enum ClipboardImageSweeper {

    /// 目录内文件名；目录不存在或不可读返回 nil（调用方按「无文件可删」处理，不报错）
    public static func fileNames(in directory: URL) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    /// 删除指定文件名，逐个 do/catch；失败只记 warning，不向上抛
    /// - Returns: 实际删除的文件数
    @discardableResult
    public static func remove(fileNames: [String], in directory: URL,
                              logger: LoggingService) -> Int {
        guard !fileNames.isEmpty else { return 0 }
        let manager = FileManager.default
        var removed = 0
        for fileName in fileNames {
            let url = directory.appendingPathComponent(fileName)
            do {
                try manager.removeItem(at: url)
                removed += 1
            } catch {
                // 路径不进 public 日志：先过 LogRedaction
                logger.warning("剪贴板图片删除失败：\(LogRedaction.path(url.path)) — \(error.localizedDescription)")
            }
        }
        return removed
    }
}
