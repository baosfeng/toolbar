import Foundation

// MARK: - 音效文件错误

/// 自定义音效目录的错误
public enum NotificationSoundStoreError: String, Error, Sendable {
    /// 名字不可用（清洗后为空或路径穿越）
    case invalidName
    /// 目标文件不存在
    case notFound
    /// 拷贝失败（源不可读 / 目标不可写）
    case copyFailed
    /// 超出体积上限
    case tooLarge

    public var message: String {
        switch self {
        case .invalidName: return "音效名不可用"
        case .notFound: return "音效文件不存在"
        case .copyFailed: return "音效文件写入失败"
        case .tooLarge: return "音效文件超过 10 MB"
        }
    }
}

// MARK: - 自定义音效目录

/// 自定义音效目录 — 只管「自己目录内的文件」，是所有文件操作的唯一入口
///
/// 安全口径：
/// - 只接受文件名（不含路径）；构造 URL 前统一走 sanitizedDisplayName，
///   再校验标准化后的路径确实落在本目录内（防 ../ 与符号链接穿越）；
/// - import 只做拷贝，不移动用户原文件；
/// - remove 只删本目录内的普通文件。
///
/// 目录位置：~/Library/Application Support/NetworkMonitor/Sounds（自己管理、可统计、可清空）。
public final class NotificationSoundFileStore: @unchecked Sendable {

    /// 本模块使用的文件扩展名（导入时统一转成 AIFF，播放与通知目录共用一份）
    public static let storedExtension = "aiff"

    /// 文件系统句柄（测试可注入临时目录）
    private let fileManager: FileManager
    /// 音效目录（已标准化）
    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory.standardizedFileURL
    }

    /// 默认目录：~/Library/Application Support/NetworkMonitor/Sounds
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NetworkMonitor/Sounds", isDirectory: true)
    }

    // MARK: - 查询

    /// 目录内全部音效文件名（按名字排序；目录不存在时为空）
    public func files() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let items = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return items
            .filter { !$0.hasPrefix(".") && SoundFileValidator.fileExtension(of: $0) == Self.storedExtension }
            .sorted()
    }

    /// 文件名 → 目录内 URL（名字非法或越出目录时返回 nil）
    public func url(for fileName: String) -> URL? {
        guard let safe = SoundFileValidator.sanitizedDisplayName(fileName) else { return nil }
        let candidate = directory.appendingPathComponent("\(safe).\(Self.storedExtension)")
        return contains(candidate) ? candidate : nil
    }

    /// 展示用标题（去掉扩展名）
    public func displayTitle(for fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// 目录占用字节数
    public func totalBytes() -> Int {
        lock.lock(); defer { lock.unlock() }
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.reduce(0) { sum, name in
            let url = directory.appendingPathComponent(name)
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            return sum + (size ?? 0)
        }
    }

    // MARK: - 写入

    /// 导入一份已准备好的音频文件（调用方负责转码成 AIFF），返回落盘后的文件名
    ///
    /// - Parameters:
    ///   - source: 已转码好的临时文件（本方法只拷贝）
    ///   - displayName: 用户可见名（为空时用源文件名）；重名自动加序号
    @discardableResult
    public func importPreparedFile(from source: URL, displayName: String?) throws -> String {
        let resolvedName = displayName ?? source.deletingPathExtension().lastPathComponent
        guard let base = SoundFileValidator.sanitizedDisplayName(resolvedName) else {
            throw NotificationSoundStoreError.invalidName
        }
        let size = (try? fileManager.attributesOfItem(atPath: source.path)[.size] as? Int) ?? nil
        if let size, size > SoundFileValidator.maxBytes { throw NotificationSoundStoreError.tooLarge }

        lock.lock(); defer { lock.unlock() }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = uniqueURL(forBase: base)
        do {
            try fileManager.copyItem(at: source, to: target)
        } catch {
            throw NotificationSoundStoreError.copyFailed
        }
        return target.lastPathComponent
    }

    /// 重命名（只改文件名，不动内容），返回新文件名
    @discardableResult
    public func rename(_ fileName: String, to newDisplayName: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let source = url(for: fileName) else { throw NotificationSoundStoreError.notFound }
        guard let base = SoundFileValidator.sanitizedDisplayName(newDisplayName) else {
            throw NotificationSoundStoreError.invalidName
        }
        let target = uniqueURL(forBase: base, excluding: source)
        do {
            try fileManager.moveItem(at: source, to: target)
        } catch {
            throw NotificationSoundStoreError.copyFailed
        }
        return target.lastPathComponent
    }

    /// 删除（只删本目录内的文件；不存在时静默）
    public func remove(_ fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let target = url(for: fileName) else { throw NotificationSoundStoreError.notFound }
        guard fileManager.fileExists(atPath: target.path) else { return }
        do {
            try fileManager.removeItem(at: target)
        } catch {
            throw NotificationSoundStoreError.copyFailed
        }
    }

    /// 清空目录（设置页「清空自定义音效」）
    public func removeAll() {
        files().forEach { try? remove($0) }
    }

    // MARK: - 内部

    /// 路径是否真的落在本目录内（防穿越的最后一道闸）
    private func contains(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        let root = directory.standardizedFileURL.path
        return target.hasPrefix(root + "/") && !target.contains("/../")
    }

    /// 取一个不重名的目标 URL（base.aiff / base 2.aiff / base 3.aiff …）
    private func uniqueURL(forBase base: String, excluding: URL? = nil) -> URL {
        var candidate = directory.appendingPathComponent("\(base).\(Self.storedExtension)")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path), candidate != excluding {
            candidate = directory.appendingPathComponent("\(base) \(index).\(Self.storedExtension)")
            index += 1
            if index > 999 { break }
        }
        return candidate
    }
}
