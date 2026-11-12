import Foundation

// MARK: - 文件分类

/// 剪贴板「文件」条目的展示分类 — 决定卡片图标与无障碍可读名
///
/// 判据一律是**扩展名白名单**（显式列举），不做「非图片即文档」这类黑名单推断：
/// 未知扩展名与空扩展名统一落到 `.other`，宁可保守也不让卡片图标说谎。
public enum ClipboardFileCategory: String, CaseIterable, Sendable {
    /// 图片（png / jpg / heic…）
    case image
    /// 视频（mp4 / mov…）
    case video
    /// 音频（mp3 / wav…）
    case audio
    /// 文档与表格（pdf / docx / xlsx / md…）
    case document
    /// 代码与配置（swift / ts / json / sh…）
    case code
    /// 压缩与归档（zip / 7z / tar.gz…）
    case archive
    /// 可执行与安装包（app / pkg / exe…）
    case executable
    /// 其余（无扩展名、未知扩展名、多文件混合）
    case other

    /// 中文标签（无障碍可读名与提示文案使用，不含 emoji）
    public var label: String {
        switch self {
        case .image: return "图片文件"
        case .video: return "视频文件"
        case .audio: return "音频文件"
        case .document: return "文档文件"
        case .code: return "代码文件"
        case .archive: return "压缩包"
        case .executable: return "可执行文件"
        case .other: return "文件"
        }
    }

    /// SF Symbol 名（保守常见符号，macOS 14 均可用；与项目既有图标同族）
    public var symbolName: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc.text"
        case .code: return "curlybraces"
        case .archive: return "archivebox"
        case .executable: return "hammer"
        case .other: return "doc"
        }
    }
}

// MARK: - 扩展名分类

/// 文件条目的分类器 — 纯函数、不碰文件系统（按路径扩展名判定，不读盘）
public enum ClipboardFileClassifier {

    /// 单条路径的分类：扩展名取不到或不在白名单 → `.other`
    public static func category(forPath path: String) -> ClipboardFileCategory {
        guard let ext = normalizedExtension(of: path) else { return .other }
        return category(forExtension: ext)
    }

    /// 多条路径的分类：空数组 → nil；全部同类 → 该类别；混合（含未知） → `.other`
    ///
    /// 混合时返回 `.other` 而不是「第一条的类别」：一张卡片只会画一个图标，
    /// 取多数派或首条都会让图标撒谎。
    public static func category(forPaths paths: [String]) -> ClipboardFileCategory? {
        guard !paths.isEmpty else { return nil }
        let categories = paths.map { category(forPath: $0) }
        let first = categories[0]
        return categories.allSatisfy { $0 == first } ? first : .other
    }

    /// 归一化扩展名：去首尾空白、转小写；空串 → nil
    public static func normalizedExtension(of path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (trimmed as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext.lowercased()
    }

    /// 扩展名 → 类别（白名单显式列举）
    public static func category(forExtension ext: String) -> ClipboardFileCategory {
        switch ext {
        // 图片
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg", "icns":
            return .image
        // 视频
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "mts":
            return .video
        // 音频
        case "mp3", "wav", "aiff", "aif", "m4a", "flac", "aac", "ogg", "opus", "caf", "wma":
            return .audio
        // 文档与表格
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers",
             "txt", "md", "rtf", "csv", "tsv", "epub":
            return .document
        // 代码与配置
        case "swift", "h", "m", "mm", "c", "cc", "cpp", "hpp", "js", "mjs", "cjs", "ts", "tsx", "jsx",
             "py", "rb", "go", "rs", "java", "kt", "kts", "sh", "bash", "zsh", "fish",
             "json", "yaml", "yml", "toml", "xml", "plist", "html", "htm", "css", "scss", "less",
             "vue", "sql", "php", "lua", "dart", "gradle":
            return .code
        // 压缩与归档
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "lz4", "dmg":
            return .archive
        // 可执行与安装包
        case "app", "exe", "pkg", "bin", "appimage", "msi", "deb", "rpm":
            return .executable
        default:
            return .other
        }
    }
}
