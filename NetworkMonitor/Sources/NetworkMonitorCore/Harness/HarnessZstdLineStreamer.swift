import Foundation

// MARK: - zstd 行流式读取

/// 解压并逐行读取 JSONL —— **内置 libzstd 优先，zstd 可执行文件作为备选**
///
/// 设计说明：
/// - Core 不得 import AppKit，也不引入第三方 Swift 包（Package.swift 零新依赖）；
/// - **内置解码**：随包携带 `libzstd.dylib`，用 `dlopen`/`dlsym` 调 `ZSTD_decompressStream`
///   （见 HarnessZstdDecoder）。这是「第三方机器没装 zstd 也能读到数据」的主路径；
/// - **可执行文件备选**：内置解码不可用（包内 dylib 缺失 / 系统也没装）时，
///   走 `zstd -dc` 子进程，探测链见 HarnessZstdLocator；
/// - 两条路径的行切分语义必须完全一致（同一份逐块切分实现），否则会出现
///   「换台机器统计口径变了」这类最难查的问题。
public struct HarnessZstdLineStreamer: HarnessLineStreaming {
    /// 默认探测的 zstd 路径（转发自 HarnessZstdLocator，保留旧名以免调用点大面积改动）
    public static let defaultExecutableCandidates = HarnessZstdLocator.defaultExecutableCandidates

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
    /// 已定位到的可执行文件路径（不可用时为 nil；内置解码可用时也可能为 nil）
    private let executablePath: String?
    /// 内置解码器（nil = 不可用，降级到可执行文件）
    private let decoder: HarnessZstdDecoder?
    /// 日志服务（部分解压等降级情况需要留痕）
    private let logger: LoggingService

    /// 正式构造：内置解码优先，其次 zstd 可执行文件
    ///
    /// - Parameters:
    ///   - bundledDirectory: 包内资源目录（`Contents/Resources`，含 libzstd 与可选 zstd）
    ///   - loginShellLookup: 是否最后问一次登录 shell（测试传 false 以保证确定性）
    ///   - preferBuiltInDecoder: 强制关闭内置解码（测试降级路径用）
    public init(
        executableCandidates: [String] = HarnessZstdLineStreamer.defaultExecutableCandidates,
        searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
        bundledDirectory: String? = HarnessZstdLocator.bundledDirectory(),
        loginShellLookup: Bool = true,
        preferBuiltInDecoder: Bool = true,
        logger: LoggingService = AppContext.shared.logger
    ) {
        self.logger = logger
        let builtIn = preferBuiltInDecoder
            ? HarnessZstdDecoder.make(bundledDirectory: bundledDirectory, logger: logger)
            : nil
        self.decoder = builtIn
        let found = HarnessZstdLocator.locate(candidates: executableCandidates,
                                              searchPath: searchPath,
                                              bundledDirectory: bundledDirectory,
                                              loginShellLookup: loginShellLookup)
        self.executablePath = found
        if let builtIn {
            // 内置解码可用：toolPath 说明用的是哪份 libzstd（设置页据此回答「靠什么解压的」）
            self.availability = .available(toolPath: builtIn.libraryPath + "（内置解码）")
        } else if let found {
            self.availability = .available(toolPath: found)
        } else {
            self.availability = .toolMissing(
                searchedPaths: HarnessZstdLocator.searchedPaths(candidates: executableCandidates,
                                                                searchPath: searchPath,
                                                                bundledDirectory: bundledDirectory,
                                                                loginShellLookup: loginShellLookup)
            )
        }
    }

    /// 直接指定可用性（测试用：模拟不可用降级路径）
    public init(availability: HarnessSourceAvailability, logger: LoggingService = AppContext.shared.logger) {
        self.executablePath = nil
        self.decoder = nil
        self.availability = availability
        self.logger = logger
    }

    // MARK: - 流式读取

    public func streamLines(
        from path: String,
        isCancelled: @Sendable () -> Bool,
        onLine: (Data) -> Void
    ) throws {
        if let decoder {
            try streamWithBuiltInDecoder(decoder, from: path, isCancelled: isCancelled, onLine: onLine)
            return
        }
        guard case .available = availability, let executablePath else {
            throw HarnessTokenError.sourceUnavailable(availability.displayMessage)
        }
        try streamWithProcess(executablePath: executablePath, from: path,
                              isCancelled: isCancelled, onLine: onLine)
    }

    // MARK: - 内置解码路径

    /// 用内置 libzstd 流式解码并按块切行（与子进程路径共用 `LineSplitter`）
    private func streamWithBuiltInDecoder(
        _ decoder: HarnessZstdDecoder,
        from path: String,
        isCancelled: @Sendable () -> Bool,
        onLine: (Data) -> Void
    ) throws {
        // 同 streamWithProcess：协议里的 onLine 非逃逸，切行器要存属性，
        // 用 withoutActuallyEscaping 显式声明「不会真的逃出本函数」
        try withoutActuallyEscaping(onLine) { escapingLine in
            var splitter = LineSplitter(onLine: escapingLine)
            try decoder.decode(path: path, isCancelled: isCancelled) { buffer in
                // 指针生命周期仅限回调内：立刻拷成 Data（单块 128KB，成本可忽略）
                splitter.append(Data(buffer))
            }
            splitter.finish()
        }
    }

    // MARK: - 可执行文件路径

    /// 用 `zstd -dc` 子进程解压并按块切行
    private func streamWithProcess(
        executablePath: String,
        from path: String,
        isCancelled: @Sendable () -> Bool,
        onLine: (Data) -> Void
    ) throws {
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
        var cancelled = false
        var totalBytes = 0

        // 协议里的 onLine 非逃逸，LineSplitter 需要把它存成属性：
        // withoutActuallyEscaping 显式声明「它不会真的逃出本函数」，
        // 既不改协议签名，也不引入「闭包逃逸访问已释放栈」的风险。
        withoutActuallyEscaping(onLine) { escapingLine in
            var splitter = LineSplitter(onLine: escapingLine)
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
                    splitter.append(chunk)
                    return .continueReading
                }
                if outcome == .endOfStream { break }
            }
            splitter.finish()
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

// MARK: - 逐块切行

/// 逐块字节流 → 完整行（两条解压路径共用，保证统计口径不随解压方式漂移）
///
/// 语义要点（由既有测试固化，勿改）：
/// - 一行跨多块时增量追加，不重复整条复制（否则 O(行长²)）；
/// - 块**恰以换行结尾**时多产出一个尾随空行 —— 这是旧实现 `split(omittingEmptySubsequences: false)`
///   的产物，已有测试按此计数；
/// - 结束时若有未换行的尾部，作为最后一行产出。
private struct LineSplitter {
    private let onLine: (Data) -> Void
    private var carry = Data()

    init(onLine: @escaping (Data) -> Void) {
        self.onLine = onLine
    }

    mutating func append(_ chunk: Data) {
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
        if endsWithNewline { onLine(Data()) }
    }

    /// 收尾：把未换行的尾部作为最后一行产出
    mutating func finish() {
        if !carry.isEmpty {
            onLine(carry)
            carry = Data()
        }
    }
}
