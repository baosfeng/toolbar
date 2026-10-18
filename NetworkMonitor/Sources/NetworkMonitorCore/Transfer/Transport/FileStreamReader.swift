import CryptoKit
import Foundation

// MARK: - 流式读取

/// 文件读取与摘要计算 — 发送端生成清单、断点续传续传都走这里
///
/// 所有读取按 `TransferProtocol.chunkSize`（64 KiB）分块，内存占用与文件大小无关。
public enum FileStreamReader {

    /// 计算整文件 sha256（十六进制小写）
    public static func sha256(of url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw TransferError.ioFailed("无法读取 \(url.lastPathComponent)：\(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: TransferProtocol.chunkSize) ?? Data()
            } catch {
                throw TransferError.ioFailed("读取 \(url.lastPathComponent) 失败：\(error.localizedDescription)")
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 从 `offset` 起分块读取，逐块回调（回调抛错即中止）
    public static func readChunks(url: URL, from offset: Int64 = 0,
                                  chunkSize: Int = TransferProtocol.chunkSize,
                                  onChunk: (Data) throws -> Void) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw TransferError.ioFailed("无法读取 \(url.lastPathComponent)：\(error.localizedDescription)")
        }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, offset)))

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: max(1, chunkSize)) ?? Data()
            } catch {
                throw TransferError.ioFailed("读取 \(url.lastPathComponent) 失败：\(error.localizedDescription)")
            }
            if chunk.isEmpty { break }
            try onChunk(chunk)
        }
    }

    /// 文件大小（取不到返回 nil）
    public static func size(of url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    /// 按扩展名猜 MIME（未知回落到 octet-stream，不引入第三方库）
    public static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "apk": return "application/vnd.android.package-archive"
        default: return "application/octet-stream"
        }
    }
}
