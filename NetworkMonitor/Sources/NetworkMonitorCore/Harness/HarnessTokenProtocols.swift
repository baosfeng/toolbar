import Foundation

// MARK: - 数据源可用性

/// 数据源可用性 —— 外部 zstd 或会话目录缺失时的明确状态
///
/// 降级原则：不崩溃、不静默返回空数据；调用方据此在 UI 给出解释。
public enum HarnessSourceAvailability: Sendable, Equatable {
    /// 可用，toolPath 为解压可执行文件路径
    case available(toolPath: String)
    /// zstd 缺失：searchedPaths 为探测过的路径
    case toolMissing(searchedPaths: [String])
    /// 会话目录不存在
    case sessionsDirectoryMissing(path: String)

    /// 是否可用
    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// 供 UI 展示的说明文案（中文）
    public var displayMessage: String {
        switch self {
        case .available(let toolPath):
            return "DSH 会话数据源可用（zstd: " + toolPath + "）"
        case .toolMissing(let searchedPaths):
            return "未找到 zstd 解压工具，无法读取 DSH 会话；已探测: " + searchedPaths.joined(separator: ", ")
        case .sessionsDirectoryMissing(let path):
            return "未找到 DSH 会话目录: " + path
        }
    }
}

// MARK: - 索引状态

/// 索引进度
public struct HarnessIndexProgress: Sendable, Equatable {
    public let completedFiles: Int
    public let totalFiles: Int
    public let currentFile: String
    public let parsedSessions: Int

    public init(completedFiles: Int, totalFiles: Int, currentFile: String, parsedSessions: Int) {
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentFile = currentFile
        self.parsedSessions = parsedSessions
    }

    /// 0...1 进度比例
    public var fraction: Double {
        totalFiles > 0 ? min(1, Double(completedFiles) / Double(totalFiles)) : 0
    }
}

/// 索引状态机
public enum HarnessIndexingState: Sendable, Equatable {
    /// 空闲（尚未开始或已取消）
    case idle
    /// 正在索引
    case indexing(HarnessIndexProgress)
    /// 已完成，数据可用
    case ready
    /// 失败（数据源不可用或落库失败），message 为原因
    case failed(message: String)

    /// 是否正在索引
    public var isIndexing: Bool {
        if case .indexing = self { return true }
        return false
    }
}

// MARK: - 取消令牌

/// 取消令牌 —— 跨线程共享的取消标志
public final class HarnessCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    /// 请求取消
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// 是否已取消
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

// MARK: - 错误

/// Harness token 数据层错误（按领域划分，不用字符串抛错）
public enum HarnessTokenError: Error, Equatable {
    /// 数据源不可用（zstd / 会话目录缺失）
    case sourceUnavailable(String)
    /// 调用方请求取消
    case cancellationRequested
    /// 解压失败
    case decompressionFailed(path: String, reason: String)
    /// 会话目录不可读
    case sessionsDirectoryUnreadable(path: String)
}

extension HarnessTokenError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let message): return message
        case .cancellationRequested: return "索引已取消"
        case .decompressionFailed(let path, let reason): return "解压失败（" + path + "）：" + reason
        case .sessionsDirectoryUnreadable(let path): return "会话目录不可读：" + path
        }
    }
}

// MARK: - 领域协议

/// 解压行流式读取（把外部 zstd 进程抽象出来，便于无 zstd 环境下测试）
public protocol HarnessLineStreaming: Sendable {
    /// 当前数据源可用性
    var availability: HarnessSourceAvailability { get }

    /// 逐行读取解压后的 JSONL
    /// - Parameters:
    ///   - path: 压缩文件绝对路径
    ///   - isCancelled: 取消判定，须在读取循环中被反复调用
    ///   - onLine: 每读到完整一行回调一次（不含换行符）
    func streamLines(
        from path: String,
        isCancelled: @Sendable () -> Bool,
        onLine: (Data) -> Void
    ) throws
}

/// 会话扫描器（发现文件 + 解析单个文件）
public protocol HarnessSessionScanning: Sendable {
    /// 当前数据源可用性
    var availability: HarnessSourceAvailability { get }

    /// 发现全部会话文件
    func discoverSessions() throws -> [HarnessSessionFile]

    /// 扫描单个会话文件
    /// - Parameters:
    ///   - file: 待扫描文件
    ///   - isCancelled: 取消判定
    ///   - onLinesRead: 已读行数进度回调（每若干行一次，避免过度回调）
    func scan(
        file: HarnessSessionFile,
        isCancelled: @Sendable () -> Bool,
        onLinesRead: (@Sendable (Int) -> Void)?
    ) throws -> HarnessSessionScanResult
}

/// Token 索引仓储（SQLite 落库与聚合查询）
///
/// 由 DatabaseManager 扩展实现，复用既有连接与串行队列，不新建第二套连接管理。
public protocol HarnessTokenRepository: AnyObject, Sendable {
    /// 幂等建表；返回是否可用
    func migrateHarnessSchema() -> Bool

    /// 读取已有扫描记录（键为文件绝对路径）
    func harnessScanRecords() -> [String: HarnessSessionScanRecord]

    /// 覆盖写入单个会话的事件与扫描记录（单事务，先删后插）
    func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String
    ) -> Bool

    /// 聚合查询（今日 / 本周 / 累计 / 按天 / 按项目 / 按模型）
    func harnessAggregate(now: Date) -> HarnessAggregate

    /// 已入库事件总数
    func harnessEventCount() -> Int

    /// 清空索引（重建用）
    func harnessClearAll() -> Bool
}

/// 对外门面服务
public protocol HarnessUsageServicing: AnyObject, Sendable {
    /// 当前索引状态
    var state: HarnessIndexingState { get }
    /// 数据源可用性
    var availability: HarnessSourceAvailability { get }

    /// 读取快照（线程安全，可任意线程调用）
    func snapshot() -> HarnessUsageSnapshot

    /// 按需增量刷新（后台串行执行，不阻塞调用线程）
    func refreshIfNeeded(completion: (@Sendable () -> Void)?)

    /// 全量重建索引（后台串行执行）
    func rebuildIndex(completion: (@Sendable () -> Void)?)

    /// 取消正在进行的索引
    func cancelIndexing()
}

// MARK: - 协议默认实现

public extension HarnessUsageServicing {
    func refreshIfNeeded() { refreshIfNeeded(completion: nil) }
    func rebuildIndex() { rebuildIndex(completion: nil) }
}
