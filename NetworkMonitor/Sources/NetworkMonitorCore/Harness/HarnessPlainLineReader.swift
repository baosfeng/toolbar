import Foundation

// MARK: - 纯文本 JSONL 逐行读取

/// 纯文本 JSONL 的行流式读取（Claude / Codex 的会话文件是明文，不需要 zstd）
///
/// 与 `HarnessZstdLineStreamer` 的分工：那个解压 zstd 再分行，这个只分行。两者都符合
/// `HarnessLineStreaming`，扫描器因此不必按来源分支处理 IO。
///
/// 分块读 + 保留半行尾巴：一次读 64 KiB，跨块的半行留到下一块拼上；
/// 文件尾没有换行也要把最后一行吐出去（会话被强杀时很常见）。
public struct HarnessPlainLineReader: HarnessLineStreaming {

    /// 单次读取块大小
    private static let chunkSize = 64 * 1024

    public init() {}

    /// 纯文本来源不需要外部工具
    public var availability: HarnessSourceAvailability { .available(toolPath: "") }

    public func streamLines(
        from path: String,
        isCancelled: @Sendable () -> Bool,
        onLine: (Data) -> Void
    ) throws {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw HarnessPlainReadError.openFailed(path: path)
        }
        defer { try? handle.close() }
        var pending = Data()
        while true {
            if isCancelled() { throw HarnessTokenError.cancellationRequested }
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: Self.chunkSize)
            } catch {
                throw HarnessPlainReadError.readFailed(path: path, reason: String(describing: error))
            }
            guard let chunk, !chunk.isEmpty else { break }
            pending.append(chunk)
            // 逐行回调：用 autoreleasepool 保证每行产生的 JSON 中间体按行回收，
            // 否则驻留量随已解析字节数单调增长（与 zstd 线路同理）
            while let breakIndex = pending.firstIndex(of: 0x0A) {
                // 先拷出本行再删缓冲：Data 被删掉一段后旧切片的下标全部失效
                let line = Data(pending[pending.startIndex..<breakIndex])
                pending.removeSubrange(pending.startIndex...breakIndex)
                autoreleasepool { onLine(line) }
            }
        }
        if !pending.isEmpty {
            autoreleasepool { onLine(pending) }
        }
    }
}

// MARK: - 错误

/// 纯文本读取错误（按领域划分，不用字符串抛错）
public enum HarnessPlainReadError: Error, Equatable {
    /// 打不开（权限 / 文件已被裁掉）
    case openFailed(path: String)
    /// 读失败（卷掉线 / IO 错误）
    case readFailed(path: String, reason: String)
}

extension HarnessPlainReadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .openFailed(let path): return "会话文件无法打开：" + path
        case .readFailed(let path, let reason): return "会话文件读取失败（" + path + "）：" + reason
        }
    }
}
