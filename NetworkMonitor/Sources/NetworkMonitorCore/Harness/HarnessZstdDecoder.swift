import Foundation

// MARK: - libzstd 的 C 结构体镜像

/// 与 libzstd 的 `ZSTD_inBuffer` 逐字段对应（字段顺序与类型不可改，C ABI 直通）
struct ZSTDInBuffer {
    var src: UnsafeRawPointer?
    var size: Int
    var pos: Int
}

/// 与 libzstd 的 `ZSTD_outBuffer` 逐字段对应
struct ZSTDOutBuffer {
    var dst: UnsafeMutableRawPointer?
    var size: Int
    var pos: Int
}

// MARK: - 内置 zstd 解码（dlopen libzstd，不引入第三方 Swift 包）

/// libzstd 流式解码器 —— 用 dlopen 直接调 C 接口，兼容多帧拼接的会话文件
///
/// ## 为什么不是 Compression framework
///
/// 本轮实测（macOS 27.0.1，SDK 12.1 / 26 / 27 全部确认）：
/// - `compression.h` 没有任何 zstd 算法 id（`COMPRESSION_ZSTD` 不存在）；
/// - 对 libcompression 做 0x0000–0xFFFF 全量试探，唯一能解 zstd 帧的是 zlib（0x0205），
///   其余 id 一律 `COMPRESSION_STATUS_ERROR`；
/// - 系统没有 libzstd（`/usr/lib/libzstd*` 不存在，dyld 共享缓存里 dlopen 全失败）；
/// - libarchive 的 zstd 过滤器只是外部程序转发（无 zstd 时报
///   `unable to run program "zstd -d -qq"`）。
///
/// 所以「纯系统 API 解 zstd」这条路不存在。可行且不引第三方 Swift 包的做法是
/// **随包携带 libzstd.dylib，用 dlopen + dlsym 调它的流式解码 API**：包清单零新依赖，
/// 二进制由打包脚本拷进 `Contents/Resources` 并改 install_name（见 build-app.sh）。
///
/// ## 多帧语义（会话文件的真实形态）
///
/// `session.v4.jsonl.zstd` 是逐次追加的多个 zstd 帧首尾相接（实测某会话 175 帧）。
/// `ZSTD_decompressStream` 返回 0 表示「当前帧结束」，继续喂剩余字节即自动进入下一帧，
/// 因此不需要手工切帧；帧边界处输出与单帧解码逐字节一致（实测同文件解压字节数与
/// `zstd -dc` 完全相同）。
///
/// ## 失败必须可诊断
///
/// 解不出来时抛 `HarnessTokenError.decompressionFailed`（带已解字节数与 libzstd 错误名），
/// **绝不静默返回空**；文件尾部正在追加（停在帧中间）时保留已解内容并记 warning，
/// 与外部 zstd 进程路径的既有语义一致。
public final class HarnessZstdDecoder: @unchecked Sendable {

    // MARK: - libzstd 函数表

    private typealias CreateDStream = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias FreeDStream = @convention(c) (UnsafeMutableRawPointer?) -> Int
    private typealias InitDStream = @convention(c) (UnsafeMutableRawPointer?) -> Int
    /// 参数在 C 侧是 `ZSTD_outBuffer*` / `ZSTD_inBuffer*`；Swift 自定义结构体不能直接写进
    /// `@convention(c)` 签名，因此按「三个指针」声明（ABI 完全一致），调用点用
    /// `withUnsafeMutablePointer` 把结构体地址传进去。
    private typealias DecompressStream = @convention(c) (UnsafeMutableRawPointer?,
                                                        UnsafeMutableRawPointer?,
                                                        UnsafeMutableRawPointer?) -> Int
    private typealias IsError = @convention(c) (Int) -> UInt32
    private typealias GetErrorName = @convention(c) (Int) -> UnsafePointer<CChar>?

    /// 单次读取的压缩数据块大小
    static let readChunkSize = 64 * 1024
    /// 单次解码输出块大小（够大才不会因为输出空间不足反复循环）
    static let outputChunkSize = 128 * 1024

    private let handle: UnsafeMutableRawPointer
    private let createDStream: CreateDStream
    private let freeDStream: FreeDStream
    private let initDStream: InitDStream
    private let decompressStream: DecompressStream
    private let isError: IsError
    private let errorName: GetErrorName
    private let logger: LoggingService

    /// 实际加载的 dylib 路径（诊断用）
    public let libraryPath: String

    /// 随包携带的 libzstd 文件名（`Contents/Resources/libzstd.1.dylib`）
    public static let bundledLibraryName = "libzstd.1.dylib"

    // MARK: - 定位

    /// 依次尝试的 dylib 路径：包内自带 → Homebrew（两种前缀）→ MacPorts
    ///
    /// 包内自带排第一：第三方机器没有任何 Homebrew 时，只有这一条能命中。
    public static func candidateLibraryPaths(bundledDirectory: String?) -> [String] {
        var paths: [String] = []
        if let bundledDirectory, !bundledDirectory.isEmpty {
            paths.append(bundledDirectory + "/" + bundledLibraryName)
        }
        paths.append("/opt/homebrew/lib/" + bundledLibraryName)
        paths.append("/usr/local/lib/" + bundledLibraryName)
        paths.append("/opt/local/lib/" + bundledLibraryName)
        return paths
    }

    /// 按候选路径加载；都不可用（或符号缺失）返回 nil，调用方据此降级到 zstd 可执行文件
    public static func make(bundledDirectory: String? = Bundle.main.resourcePath,
                            logger: LoggingService = AppContext.shared.logger) -> HarnessZstdDecoder? {
        for path in candidateLibraryPaths(bundledDirectory: bundledDirectory) {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let decoder = HarnessZstdDecoder(libraryPath: path, logger: logger) { return decoder }
        }
        return nil
    }

    /// 加载指定 dylib（符号不全时返回 nil，不崩溃）
    public init?(libraryPath: String, logger: LoggingService = AppContext.shared.logger) {
        guard let handle = dlopen(libraryPath, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let create = symbol("ZSTD_createDStream", as: CreateDStream.self),
              let free = symbol("ZSTD_freeDStream", as: FreeDStream.self),
              let initialize = symbol("ZSTD_initDStream", as: InitDStream.self),
              let decompress = symbol("ZSTD_decompressStream", as: DecompressStream.self),
              let isErr = symbol("ZSTD_isError", as: IsError.self),
              let name = symbol("ZSTD_getErrorName", as: GetErrorName.self) else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.createDStream = create
        self.freeDStream = free
        self.initDStream = initialize
        self.decompressStream = decompress
        self.isError = isErr
        self.errorName = name
        self.libraryPath = libraryPath
        self.logger = logger
    }

    deinit {
        dlclose(handle)
    }

    // MARK: - 流式解码

    /// 解码整份文件，按块回调解压后的字节（块边界与行无关，由上层做行切分）
    ///
    /// - Parameters:
    ///   - path: 压缩文件路径（错误文案用）
    ///   - isCancelled: 取消判定（每块检查一次）
    ///   - onOutput: 每块解压字节；指针生命周期仅限闭包内
    /// - Returns: 解压出的总字节数
    @discardableResult
    public func decode(path: String,
                       isCancelled: @Sendable () -> Bool,
                       onOutput: (UnsafeRawBufferPointer) -> Void) throws -> Int {
        guard let stream = FileHandle(forReadingAtPath: path) else {
            throw HarnessTokenError.decompressionFailed(path: path, reason: "无法打开会话文件")
        }
        defer { try? stream.close() }
        guard let dctx = createDStream() else {
            throw HarnessTokenError.decompressionFailed(path: path, reason: "无法创建 zstd 解码上下文")
        }
        defer { _ = freeDStream(dctx) }
        _ = initDStream(dctx)

        var output = [UInt8](repeating: 0, count: Self.outputChunkSize)
        var produced = 0
        /// 最近一次 `ZSTD_decompressStream` 的返回值（0 = 恰好停在帧尾）
        var lastReturn = 0
        var sawInput = false

        while true {
            if isCancelled() { throw HarnessTokenError.cancellationRequested }
            let chunk: Data
            do {
                chunk = try stream.read(upToCount: Self.readChunkSize) ?? Data()
            } catch {
                throw HarnessTokenError.decompressionFailed(
                    path: path, reason: "读取失败：" + error.localizedDescription)
            }
            if chunk.isEmpty { break }
            sawInput = true
            try chunk.withUnsafeBytes { raw in
                var inBuffer = ZSTDInBuffer(src: raw.baseAddress, size: chunk.count, pos: 0)
                while inBuffer.pos < inBuffer.size {
                    let before = inBuffer.pos
                    let step = try pump(dctx: dctx, inBuffer: &inBuffer, output: &output,
                                        produced: produced, path: path, onOutput: onOutput)
                    produced += step.written
                    lastReturn = step.ret
                    // 零进度保护：既没消费输入也没产出输出时，继续循环就是死等
                    if inBuffer.pos == before && step.written == 0 { break }
                }
            }
        }

        guard sawInput else {
            // 空文件是合法输入（会话刚创建），不是错误
            return 0
        }
        if lastReturn != 0 {
            // 停在帧中间：文件可能正在写入，也可能被截断
            guard produced > 0 else {
                throw HarnessTokenError.decompressionFailed(
                    path: path, reason: "内置 zstd 未产出任何数据（会话文件可能损坏或尚未写入）")
            }
            logger.warning("内置 zstd 解码在帧中间结束（文件可能正在写入），已保留可解析内容: "
                           + LogRedaction.path(path))
        }
        return produced
    }

    /// 推进一次解码（一次 `ZSTD_decompressStream` 调用）
    private func pump(dctx: UnsafeMutableRawPointer,
                      inBuffer: inout ZSTDInBuffer,
                      output: inout [UInt8],
                      produced: Int,
                      path: String,
                      onOutput: (UnsafeRawBufferPointer) -> Void) throws -> (ret: Int, written: Int) {
        try output.withUnsafeMutableBytes { outRaw -> (ret: Int, written: Int) in
            var outBuffer = ZSTDOutBuffer(dst: outRaw.baseAddress,
                                          size: Self.outputChunkSize, pos: 0)
            let ret: Int = withUnsafeMutablePointer(to: &outBuffer) { outPointer in
                withUnsafeMutablePointer(to: &inBuffer) { inPointer in
                    decompressStream(dctx,
                                     UnsafeMutableRawPointer(outPointer),
                                     UnsafeMutableRawPointer(inPointer))
                }
            }
            if isError(ret) != 0 {
                let name = errorName(ret).map { String(cString: $0) } ?? "未知错误"
                throw HarnessTokenError.decompressionFailed(
                    path: path,
                    reason: "内置 zstd 解码失败（已解 " + String(produced) + " 字节）：" + name)
            }
            if outBuffer.pos > 0 {
                onOutput(UnsafeRawBufferPointer(start: outBuffer.dst, count: outBuffer.pos))
            }
            return (ret, outBuffer.pos)
        }
    }
}