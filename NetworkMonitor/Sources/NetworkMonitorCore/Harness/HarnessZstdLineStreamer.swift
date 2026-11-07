import Foundation

// MARK: - zstd 行流式读取

/// 通过外部 zstd 进程解压并逐行读取 JSONL
///
/// 设计说明：
/// - Core 不得 import AppKit，也不引入第三方压缩库，故用 Foundation.Process 调系统 zstd
/// - 可执行文件探测顺序：显式候选路径 → PATH 各目录；都找不到时 availability 为 toolMissing
/// - 读取按块增量进行，块间检查取消标志；stderr 接到 nullDevice 避免管道写满死锁
public struct HarnessZstdLineStreamer: HarnessLineStreaming {
    /// 默认探测的 zstd 路径
    public static let defaultExecutableCandidates = [
        "/opt/homebrew/bin/zstd",
        "/usr/local/bin/zstd",
        "/usr/bin/zstd",
    ]

    /// 单次读取块大小
    static let readChunkSize = 64 * 1024

    /// 单轮读取的结果（用于跳出块级 autoreleasepool 后决定是否结束）
    private enum BlockOutcome {
        /// 读到数据，继续下一轮
        case continueReading
        /// 管道已关闭（读到空块）
        case endOfStream
    }

    public let availability: HarnessSourceAvailability
    /// 已定位到的可执行文件路径（不可用时为 nil）
    private let executablePath: String?
    /// 日志服务（部分解压等降级情况需要留痕）
    private let logger: LoggingService

    public init(
        executableCandidates: [String] = HarnessZstdLineStreamer.defaultExecutableCandidates,
        searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
        logger: LoggingService = AppContext.shared.logger
    ) {
        self.logger = logger
        let found = HarnessZstdLineStreamer.locateExecutable(candidates: executableCandidates, searchPath: searchPath)
        self.executablePath = found
        if let found {
            self.availability = .available(toolPath: found)
        } else {
            self.availability = .toolMissing(
                searchedPaths: HarnessZstdLineStreamer.searchedPaths(candidates: executableCandidates, searchPath: searchPath)
            )
        }
    }

    /// 直接指定可用性（测试用：模拟不可用降级路径）
    public init(availability: HarnessSourceAvailability, logger: LoggingService = AppContext.shared.logger) {
        self.executablePath = nil
        self.availability = availability
        self.logger = logger
    }

    // MARK: - 探测

    /// 按候选路径与 PATH 查找可执行 zstd
    static func locateExecutable(candidates: [String], searchPath: String?) -> String? {
        for candidate in candidates where isExecutable(candidate) {
            return candidate
        }
        guard let searchPath else { return nil }
        for directory in searchPath.split(separator: ":") where !directory.isEmpty {
            let candidate = String(directory) + "/zstd"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// 探测过的路径列表（去重并限制条数，避免错误文案过长）
    static func searchedPaths(candidates: [String], searchPath: String?) -> [String] {
        var paths = candidates
        if let searchPath {
            for directory in searchPath.split(separator: ":") where !directory.isEmpty {
                paths.append(String(directory) + "/zstd")
            }
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - 流式读取

    public func streamLines(
        from path: String,
        isCancelled: @Sendable () -> Bool,
        onLine: (Data) -> Void
    ) throws {
        guard case .available = availability, let executablePath else {
            throw HarnessTokenError.sourceUnavailable(availability.displayMessage)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-dc", path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw HarnessTokenError.decompressionFailed(path: path, reason: error.localizedDescription)
        }

        let handle = outputPipe.fileHandleForReading
        var carry = Data()
        var cancelled = false
        var totalBytes = 0

        while true {
            if isCancelled() {
                cancelled = true
                break
            }
            // 一轮读取的全部中间体（NSData 块、拼接缓冲、切片）都纳入同一个池内回收。
            // 关键：availableData 返回的块是自动释放对象，若只把 onLine 包进池，
            // 这些块仍会挂到所在线程顶层池（GCD 块结束 / 主线程 runloop 才会清），
            // 实测 86MB 解压数据会因此常驻 +83MB；块级池才能把它压到 +4MB。
            let outcome: BlockOutcome = autoreleasepool {
                let chunk = handle.availableData
                if chunk.isEmpty { return .endOfStream }
                totalBytes += chunk.count
                // 直接在块内扫描换行，不再每轮把「已累积半行 + 整块」拼接后整体切分。
                // 旧写法在「一行跨多块」时是 O(行长²) 次拷贝：实测一个含 14MB 单行的会话
                // 反复整条复制，峰值 857MB；改为增量追加后，拷贝量收敛到单行长度本身。
                let endsWithNewline = chunk.last == 0x0A
                var lineStart = chunk.startIndex
                var index = chunk.startIndex
                while index < chunk.endIndex {
                    if chunk[index] == 0x0A {
                        let segment = chunk[lineStart..<index]
                        if carry.isEmpty {
                            onLine(Data(segment))
                        } else {
                            carry.append(contentsOf: segment)
                            onLine(carry)
                            carry = Data()
                        }
                        lineStart = chunk.index(after: index)
                    }
                    index = chunk.index(after: index)
                }
                if lineStart < chunk.endIndex {
                    carry.append(contentsOf: chunk[lineStart..<chunk.endIndex])
                }
                // 保留既有语义：块恰以换行结尾时多产出一个尾随空行
                // （旧实现 split(omittingEmptySubsequences: false) 的产物，已有测试固化）
                if endsWithNewline { onLine(Data()) }
                return .continueReading
            }
            if outcome == .endOfStream { break }
        }

        if !cancelled, !carry.isEmpty {
            onLine(carry)
        }

        // 收尾顺序很重要：必须先 waitUntilExit 收尸，再读 terminationStatus
        // （进程未结束时访问 terminationStatus 会抛 NSInvalidArgumentException）
        if cancelled {
            process.terminate()
        }
        process.waitUntilExit()
        try? handle.close()

        if cancelled { throw HarnessTokenError.cancellationRequested }
        if process.terminationStatus != 0 {
            // 正在写入的会话文件尾部可能不完整：只要已产出数据就保留可解析内容，
            // 仅当完全没有输出时才判定为解压失败（不静默返回空、也不整文件丢弃）
            guard totalBytes > 0 else {
                throw HarnessTokenError.decompressionFailed(
                    path: path,
                    reason: "zstd 退出码 " + String(process.terminationStatus)
                )
            }
            logger.warning("zstd 非零退出（" + String(process.terminationStatus) + "），已保留可解析内容: " + LogRedaction.path(path))
        }
    }
}
