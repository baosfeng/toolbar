import CryptoKit
import Foundation

// MARK: - 流式落盘

/// 流式文件写入 — 传输中写 `<fileId>.part`，边写边算 sha256，内存占用与文件大小无关
///
/// 续传语义：构造时若传入 `resumeOffset` > 0，会把已有 `.part` 内容先喂给 hasher，
/// 因此 `finish()` 返回的是**整个文件**的摘要，可直接与发送端清单比对。
/// 改名（`.part` → 正式名）由 Service 在摘要校验通过后执行，写入器不决定落盘名。
public final class FileStreamWriter: @unchecked Sendable {

    /// 最终落盘路径
    public let finalURL: URL
    /// 传输中的临时文件路径
    public let partURL: URL
    /// 续传起点（构造时 `.part` 已有字节数）
    public let resumeOffset: Int64

    private let lock = NSLock()
    private var handle: FileHandle?
    private var hasher = SHA256()
    private var written: Int64
    private var finalized = false
    private var cachedDigest = ""

    /// - Parameters:
    ///   - finalURL: 校验通过后的正式文件路径
    ///   - resumeOffset: `.part` 已有字节数（0 表示全新传输）
    public init(finalURL: URL, resumeOffset: Int64 = 0) throws {
        self.finalURL = finalURL
        self.partURL = finalURL.appendingPathExtension("part")
        self.resumeOffset = max(0, resumeOffset)
        self.written = max(0, resumeOffset)

        try Self.ensurePartFile(at: partURL, resumeOffset: self.resumeOffset)
        if self.resumeOffset > 0 {
            try Self.hashExistingPart(at: partURL, into: &hasher, limit: nil)
        }
        let handle = try FileHandle(forWritingTo: partURL)
        try handle.seekToEnd()
        self.handle = handle
    }

    deinit {
        try? handle?.close()
    }

    /// 已写入总字节（含续传前内容）
    public var totalWritten: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return written
    }

    /// 追加一块数据
    public func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { throw TransferError.ioFailed("写入器已关闭") }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw TransferError.ioFailed("写入 \(partURL.lastPathComponent) 失败：\(error.localizedDescription)")
        }
        hasher.update(data: data)
        written += Int64(data.count)
    }

    /// 关闭文件并返回整文件 sha256（十六进制小写）
    public func finish() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if finalized { return cachedDigest }
        guard let handle else { throw TransferError.ioFailed("写入器已关闭") }
        do {
            try handle.close()
        } catch {
            throw TransferError.ioFailed("关闭 \(partURL.lastPathComponent) 失败：\(error.localizedDescription)")
        }
        self.handle = nil
        finalized = true
        cachedDigest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return cachedDigest
    }

    /// 中断收尾：只关闭句柄、保留 `.part`（供下次续传）
    ///
    /// 与 `finish()` 的区别：不算摘要、不改名、不删文件。
    public func finishWithoutClosingDigest() {
        lock.lock()
        let handle = self.handle
        self.handle = nil
        finalized = true
        lock.unlock()
        try? handle?.close()
    }

    /// 放弃本次传输：关闭句柄并删除 `.part`
    public func discard() {
        lock.lock()
        let handle = self.handle
        self.handle = nil
        finalized = true
        lock.unlock()
        try? handle?.close()
        try? FileManager.default.removeItem(at: partURL)
    }

    // MARK: - 内部

    /// 确保 `.part` 存在，且大小与续传偏移一致（不一致时截断到该偏移）
    private static func ensurePartFile(at url: URL, resumeOffset: Int64) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil) else {
                throw TransferError.ioFailed("无法创建 \(url.lastPathComponent)")
            }
            return
        }
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size != resumeOffset else { return }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(max(0, resumeOffset)))
    }

    /// 把已有 `.part` 内容喂给 hasher（续传时保证摘要覆盖整文件）
    private static func hashExistingPart(at url: URL, into hasher: inout SHA256,
                                         limit: Int64?) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var consumed: Int64 = 0
        while true {
            if let limit, consumed >= limit { break }
            let chunk = try handle.read(upToCount: TransferProtocol.chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            consumed += Int64(chunk.count)
        }
    }
}

// MARK: - 磁盘空间预检

/// 磁盘空间预检 — `POST /offer` 阶段判定是否返回 4004
public enum DiskSpaceProbe {

    /// 目录可用空间（字节；取不到时返回 0）
    public static func availableBytes(at directory: URL) -> Int64 {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    /// 所需空间不足时抛 `diskFull`
    public static func require(bytes: Int64, at directory: URL) throws {
        guard bytes > 0 else { return }
        let available = availableBytes(at: directory)
        if available > 0, available < bytes {
            throw TransferError.diskFull(required: bytes, available: available)
        }
    }
}
