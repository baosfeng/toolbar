import Foundation
import NetworkMonitorCore

// MARK: - 预览内容载体

/// 自绘预览的内容来源 —— 三种条目各用一种载体，浮层只认这三种
///
/// 文本条目没有落盘文件，预览前写到临时 `.txt`：正文仍由浮层读回渲染，
/// 同一份文本也因此可被「用默认 App 打开」这类后续动作复用，不是一次性的中间产物。
public enum ClipboardPreviewContent: Equatable, Sendable {
    /// 图片原图（采集中已落盘的文件）
    case image(URL)
    /// 文本写出的临时 `.txt`
    case text(URL)
    /// 文件条目里第一个真实存在的路径
    case file(URL)

    /// 载体路径（浮层读内容与调试取证都只用它）
    public var url: URL {
        switch self {
        case .image(let url), .text(let url), .file(let url): return url
        }
    }
}

// MARK: - 预览项

/// 一次预览的全部输入 —— 构造完就不再回头查条目，浮层是纯展示
public struct ClipboardPreviewTarget: Equatable, Sendable {
    /// 内容载体
    public let content: ClipboardPreviewContent
    /// 标题（类型 · 尺寸 / 字数 / 文件名）
    public let title: String
    /// 叠加在正文上方的识别文字（图片条目才有；没有就是 nil）
    public let ocrText: String?
    /// 正文字符数（图片 / 文件条目为 nil）
    public let characterCount: Int?

    public init(content: ClipboardPreviewContent, title: String,
                ocrText: String? = nil, characterCount: Int? = nil) {
        self.content = content
        self.title = title
        self.ocrText = ocrText
        self.characterCount = characterCount
    }
}

// MARK: - 构造失败原因

/// 预览项构造失败的原因 —— 浮层据此给一句中文提示，不静默失败
public enum ClipboardPreviewError: Error, Equatable, Sendable {
    /// 文本条目去掉空白后没有内容
    case emptyText
    /// 图片条目缺原图路径，或原图已不在磁盘上
    case imageMissing
    /// 文件条目的路径全部不存在
    case fileMissing
    /// 临时文本写入失败
    case writeFailed
}

// MARK: - 预览项构造

/// 预览项构造 —— 纯规则 + 一次临时文件写入，不碰 AppKit（浮层与 TestRunner 共用）
public enum ClipboardPreviewBuilder {

    /// 临时目录名（`NSTemporaryDirectory()` 下的独立子目录，退出时整目录删除）
    public static let temporaryDirectoryName = "macMonitor-clipboard-preview"

    /// 默认临时目录
    public static func defaultTemporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(temporaryDirectoryName, isDirectory: true)
    }

    /// 构造预览项
    ///
    /// - Parameters:
    ///   - item: 待预览条目
    ///   - directory: 文本临时文件落点（图片 / 文件条目不会写盘）
    ///   - fileExists: 存在性判定（测试注入，默认查真实文件系统）
    ///   - fileManager: 文件管理器（测试注入）
    public static func target(for item: ClipboardItem,
                              directory: URL = defaultTemporaryDirectory(),
                              fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                              fileManager: FileManager = .default) throws -> ClipboardPreviewTarget {
        let ocrText = ClipboardOCRPolicy.displayText(for: item)
        switch item.kind {
        case .image:
            guard let path = item.imagePath, !path.isEmpty, fileExists(path) else {
                throw ClipboardPreviewError.imageMissing
            }
            let url = URL(fileURLWithPath: path)
            return ClipboardPreviewTarget(content: .image(url), title: imageTitle(for: item), ocrText: ocrText)
        case .file:
            let paths = filePaths(in: item.text ?? item.preview)
            guard let first = paths.first(where: fileExists) else {
                throw ClipboardPreviewError.fileMissing
            }
            let url = URL(fileURLWithPath: first)
            return ClipboardPreviewTarget(content: .file(url),
                                          title: "\(ClipboardItemKindLabel.label(for: item)) · \(url.lastPathComponent)",
                                          ocrText: nil)
        case .text, .rtf:
            let text = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ClipboardPreviewError.emptyText }
            let url = try writeTextFile(text, id: item.id, into: directory, fileManager: fileManager)
            return ClipboardPreviewTarget(content: .text(url),
                                          title: "\(ClipboardItemKindLabel.label(for: item)) · \(text.count) 字符",
                                          ocrText: ocrText,
                                          characterCount: text.count)
        }
    }

    /// 文本写到临时 `.txt`（文件名按条目 id，同一覆盖写，不堆碎片）
    ///
    /// 目录不存在时按需建；任何 IO 失败都收敛成 `writeFailed`，由调用方给一句提示 + 记日志。
    public static func writeTextFile(_ text: String, id: UUID, into directory: URL,
                                     fileManager: FileManager = .default) throws -> URL {
        let url = directory.appendingPathComponent("\(id.uuidString).txt")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            throw ClipboardPreviewError.writeFailed
        }
    }

    /// 删除整个预览临时目录（幂等：目录不存在也算成功）
    ///
    /// 返回是否已清空，调用方失败时只记日志 —— 临时目录残留不该阻断退出流程。
    @discardableResult
    public static func removeTemporaryDirectory(_ directory: URL,
                                                fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        do {
            try fileManager.removeItem(at: directory)
            return true
        } catch {
            return false
        }
    }

    // MARK: 内部口径

    /// 图片标题：有尺寸给「图片 宽×高」，没有就退回类型名
    private static func imageTitle(for item: ClipboardItem) -> String {
        if let width = item.imageWidth, let height = item.imageHeight, width > 0, height > 0 {
            return "图片 \(width)×\(height)"
        }
        return ClipboardItemKindLabel.label(for: item)
    }

    /// 文件条目的路径列表：正文按行存多条路径（采集侧口径），空行丢弃
    private static func filePaths(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
