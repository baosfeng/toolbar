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
    /// 会话目录存在但不可读（权限不足 / 挂在失效的卷上）
    ///
    /// 与「不存在」分开：前者用户去设置页改路径就能救，后者要修权限或者重新挂载；
    /// 旧实现把两者都并进「不存在」，界面只说「还没有可统计的会话」。
    case sessionsDirectoryUnreadable(path: String)

    /// 是否可用
    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// 按来源说人话的可用性文案
    ///
    /// `displayMessage` 是 DSH 时期的口径（「DSH 会话目录」），多来源后对 SQLite 源要说
    /// 「数据库文件」—— 用户据此才知道该去装工具、还是去改一个文件路径。
    /// 文件型来源原样复用 `displayMessage`，既有文案一个字都不变。
    public func displayMessage(source: TokenSourceID) -> String {
        // dsh 沿用原文案（既有空态与建议都基于它）
        guard source != .dsh else { return displayMessage }
        switch self {
        case .sessionsDirectoryMissing(let path):
            return (source.isSQLite ? "数据库文件不存在: " : "未找到会话目录: ") + path
        case .sessionsDirectoryUnreadable(let path):
            let what = source.isSQLite ? "数据库文件" : "会话目录"
            return what + "不可读（权限不足或卷未挂载）: " + path
        case .available(let toolPath):
            return toolPath.isEmpty ? "数据源可用（内置解析）" : displayMessage
        case .toolMissing:
            return displayMessage
        }
    }

    /// 供 UI 展示的说明文案（中文）
    public var displayMessage: String {
        switch self {
        case .available(let toolPath):
            // 空路径 = 不需要外部工具（纯 JSONL 来源，如 Claude / Codex）：别把 zstd 塞给它们
            return toolPath.isEmpty ? "数据源可用（内置 JSONL 解析）"
                                    : "DSH 会话数据源可用（zstd: " + toolPath + "）"
        case .toolMissing(let searchedPaths):
            return "未找到 zstd 解压工具，无法读取 DSH 会话；已探测: " + searchedPaths.joined(separator: ", ")
        case .sessionsDirectoryMissing(let path):
            return "未找到 DSH 会话目录: " + path
        case .sessionsDirectoryUnreadable(let path):
            return "DSH 会话目录不可读（权限不足或卷未挂载）: " + path
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
    /// 当前文件已读行数（来自 scanner 的 onLinesRead 回调；0 表示尚未回报）
    public let linesRead: Int

    public init(completedFiles: Int, totalFiles: Int, currentFile: String,
                parsedSessions: Int, linesRead: Int = 0) {
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentFile = currentFile
        self.parsedSessions = parsedSessions
        self.linesRead = linesRead
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

    /// 日志 / 看门狗用的短标签（失败原因里可能含会话目录路径，写入日志前再过 LogRedaction）
    public var logLabel: String {
        switch self {
        case .idle: return "idle"
        case .indexing(let progress):
            return "indexing \(progress.completedFiles)/\(progress.totalFiles)"
        case .ready: return "ready"
        case .failed(let message): return "failed: " + message
        }
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

    /// 当前使用的会话目录与其来源（诊断 / 设置页展示）
    var sourceResolution: HarnessSourceResolution { get }

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

public extension HarnessSessionScanning {
    /// 单来源可用性（多来源扫描器覆盖它；单来源扫描器默认就是整体可用性）
    func availability(for source: TokenSourceID) -> HarnessSourceAvailability { availability }

    /// 单来源诊断（同上）
    func diagnostics(for source: TokenSourceID) -> HarnessSourceDiagnostics {
        HarnessSourceDiagnostics.make(resolution: sourceResolution, availability: availability)
    }

    /// 默认来源：测试桩只关心扫描行为，不关心目录来源
    var sourceResolution: HarnessSourceResolution {
        HarnessSourceResolution(path: HarnessSourceDirectory.defaultSessionsRoot(),
                                origin: .homeDefault)
    }
}

// MARK: - 按来源的索引规模

/// 按来源的索引规模（设置页「索引」卡按来源分组展示）
public struct HarnessSourceIndexCount: Sendable, Equatable {
    public let source: TokenSourceID
    /// 该来源已入库的事件数
    public let eventCount: Int
    /// 该来源已建扫描记录的会话数
    public let sessionCount: Int

    public init(source: TokenSourceID, eventCount: Int, sessionCount: Int) {
        self.source = source
        self.eventCount = eventCount
        self.sessionCount = sessionCount
    }
}

/// Token 索引仓储（SQLite 落库与聚合查询）
///
/// 由 DatabaseManager 扩展实现，复用既有连接与串行队列，不新建第二套连接管理。
public protocol HarnessTokenRepository: AnyObject, Sendable {
    /// 幂等建表；返回是否可用
    func migrateHarnessSchema() -> Bool

    /// 读取已有扫描记录（键为文件绝对路径）
    func harnessScanRecords() -> [String: HarnessSessionScanRecord]

    /// 读取已有扫描记录，可按来源过滤（source == nil = 全部）
    ///
    /// 多来源后「重扫 / 清理只针对一个来源」要靠它：判据是落库记录自带的 source，
    /// 而不是从路径反推来源（路径规则会随各家版本变，落库的才可信）。
    func harnessScanRecords(source: TokenSourceID?) -> [String: HarnessSessionScanRecord]

    /// 覆盖写入单个会话的事件与扫描记录（单事务，先删后插）
    ///
    /// 未指定来源的旧入口：等价于 `source: .dsh`（既有 DSH 扫描器走这条）。
    func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String
    ) -> Bool

    /// 覆盖写入单个会话的事件与扫描记录，并打上来源标记
    ///
    /// 多来源共用 `harness_token_event` / `harness_session_scan` 同一套表，
    /// 删除与写入都按 `(session_id, source)` 定位，各家会话 id 空间互不干扰。
    /// 默认实现忽略来源（测试桩不必感知多来源）。
    func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String,
        source: TokenSourceID
    ) -> Bool

    /// 按来源统计已索引的事件数与会话数（设置页「索引」卡；只含有数据的来源）
    func harnessSourceCounts() -> [HarnessSourceIndexCount]

    /// 聚合查询（今日 / 本周 / 累计 / 按天 / 按项目 / 按模型）
    func harnessAggregate(now: Date) -> HarnessAggregate

    /// 已入库事件总数
    func harnessEventCount() -> Int

    /// 清空索引（重建用）
    func harnessClearAll() -> Bool

    /// 按范围清理索引，返回删除的事件行数
    ///
    /// **必须同时删除 `harness_session_scan` 对应行**：增量判据是 (size, mtime)，
    /// 只删事件会让那些会话在下一轮被判成「未变更」而永久跳过（假清空）。
    /// 返回 -1 表示清理失败（调用方据此不宣称「已清理」）。
    func harnessPurge(scope: HarnessRebuildScope, now: Date) -> Int

    /// 按范围预览将删除的事件行数（-1 = 查询失败）
    ///
    /// 二次确认要在**删除之前**说清规模，判据必须与 harnessPurge 完全同源；
    /// 设置页据此在范围选择器旁显示「将删除 N 条事件」。
    func harnessPurgePreview(scope: HarnessRebuildScope, now: Date) -> Int
}

public extension HarnessTokenRepository {
    /// 默认实现：不支持预览（-1 = 未知），调用方据此显示「规模未知」而不是假的 0
    func harnessPurgePreview(scope: HarnessRebuildScope, now: Date) -> Int { -1 }

    /// 默认实现：忽略来源，退回旧入口（测试桩只实现旧入口即可）
    func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String,
        source: TokenSourceID
    ) -> Bool {
        harnessReplaceSession(record: record, events: events, cwd: cwd)
    }

    /// 默认实现：不支持按来源统计（空数组 = 无数据，不是错误）
    func harnessSourceCounts() -> [HarnessSourceIndexCount] { [] }

    /// 默认实现：先全量读再按记录自带的来源过滤（测试桩只实现全量入口即可）
    func harnessScanRecords(source: TokenSourceID?) -> [String: HarnessSessionScanRecord] {
        let all = harnessScanRecords()
        guard let source else { return all }
        return all.filter { $0.value.source == source }
    }
}

/// 对外门面服务
public protocol HarnessUsageServicing: AnyObject, Sendable {
    /// 当前索引状态
    var state: HarnessIndexingState { get }
    /// 数据源可用性
    var availability: HarnessSourceAvailability { get }
    /// 数据源诊断（目录路径 + 来源 + zstd 实际路径 / 缺失原因）
    var sourceDiagnostics: HarnessSourceDiagnostics { get }

    /// 读取快照（线程安全，可任意线程调用）
    func snapshot() -> HarnessUsageSnapshot

    /// 按需增量刷新（后台串行执行，不阻塞调用线程）
    func refreshIfNeeded(completion: (@Sendable () -> Void)?)

    /// 全量重建索引（后台串行执行）
    func rebuildIndex(completion: (@Sendable () -> Void)?)

    /// 按范围清理 + 重建索引（后台串行执行；索引进行中的请求排队而不是丢弃）
    ///
    /// - Parameters:
    ///   - scope: 清理范围；nil 表示只做增量刷新
    ///   - completion: 本轮回执（数据源不可用 / 清理失败时为 nil）
    func rebuildIndex(scope: HarnessRebuildScope?,
                      completion: (@Sendable (HarnessRebuildReceipt?) -> Void)?)

    /// 热切换数据源扫描器（设置页改目录后调用；不自动开跑，由调用方跟着重建）
    func updateScanner(_ scanner: any HarnessSessionScanning)

    /// 取消正在进行的索引
    func cancelIndexing()

    /// 有未计入快照的写入时重算一次（不阻塞调用线程；无脏数据即零查询）
    func refreshSnapshotIfDirty()
}

// MARK: - 协议默认实现

public extension HarnessUsageServicing {
    func refreshIfNeeded() { refreshIfNeeded(completion: nil) }
    func rebuildIndex() { rebuildIndex(completion: nil) }
    /// 全量清理 + 重建（无回执版，兼容旧调用点）
    func rebuildIndex(scope: HarnessRebuildScope?) { rebuildIndex(scope: scope, completion: nil) }
}
