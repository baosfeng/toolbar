import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 用量设置（数据源 + 索引维护的控制器）

/// Token 用量设置页的读写中枢 —— 设置页只画界面，解析 / 落库 / 重建都在这里
///
/// 放在 App 层而不是 Core：切换目录要 new 具体扫描器（组合根授权），Core 只提供协议与纯函数。
/// 由组合根在设置页工厂里构造（同一页实例一直持有它）。
@MainActor
final class SettingsTokenController {

    /// 索引计数摘要（设置页「索引」「维护」两卡共用）
    struct Summary: Sendable, Equatable {
        /// 发现到的会话总数
        var totalSessions: Int
        /// 已建立扫描记录的会话数
        var indexedSessions: Int
        /// 已入库事件数（nil = 还在查库）
        var eventCount: Int?
        /// 最近一次完成索引的时间
        var lastScanAt: Date?
        /// 是否正在索引
        var isIndexing: Bool
    }

    private let harness: any HarnessUsageServicing
    private let store: any HarnessTokenRepository
    /// 偏好存储（跨文件访问：来源开关 / 目录 / 自动监控都走它）
    let storage: any KeyValueStorage
    private let logger: LoggingService

    init(harness: any HarnessUsageServicing,
         store: any HarnessTokenRepository,
         storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger) {
        self.harness = harness
        self.store = store
        self.storage = storage
        self.logger = logger
    }

    /// 当前数据源诊断（目录 / 来源 / zstd 实际路径或缺失原因）
    var diagnostics: HarnessSourceDiagnostics { harness.sourceDiagnostics }

    /// 立刻可用的摘要：会话数 / 最近扫描时间直接取内存快照，事件数先给「—」（要查库）
    ///
    /// 先填这一份再异步补事件数：否则设置页首帧（以及离屏快照）会是一片空白，
    /// 用户看到的是「这里什么都没读到」，而不是「正在读」。
    func immediateSummary() -> Summary {
        let snapshot = harness.snapshot()
        return Summary(totalSessions: snapshot.totalSessions,
                       indexedSessions: snapshot.indexedSessions,
                       eventCount: nil,
                       lastScanAt: snapshot.lastScanAt,
                       isIndexing: snapshot.indexingState.isIndexing)
    }

    /// 读取完整摘要（事件数要查库，放后台；结果回主线程）
    func loadSummary(completion: @escaping @MainActor (Summary) -> Void) {
        let snapshot = harness.snapshot()
        let store = self.store
        Task.detached(priority: .utility) {
            let count = store.harnessEventCount()
            let summary = Summary(totalSessions: snapshot.totalSessions,
                                  indexedSessions: snapshot.indexedSessions,
                                  eventCount: count,
                                  lastScanAt: snapshot.lastScanAt,
                                  isIndexing: snapshot.indexingState.isIndexing)
            await MainActor.run { completion(summary) }
        }
    }

    /// 切换数据目录（nil = 恢复默认：环境变量 / 默认目录重新参与解析）
    ///
    /// - Returns: 失败原因；nil 表示已切换（是否可用由调用方读 diagnostics 判断）
    func setDirectory(_ url: URL?) -> String? {
        HarnessSourceDirectory.setCustomPath(url, storage: storage)
        let resolution = HarnessSourceDirectory.resolve(storage: storage)
        let scanner = HarnessSessionScanner(resolution: resolution,
                                            streamer: HarnessZstdLineStreamer(logger: logger))
        harness.updateScanner(scanner)
        logger.info("Token 数据目录已切换为 " + resolution.origin.displayName
                    + "（" + resolution.pathText + "）")
        return scanner.availability.isAvailable ? nil : scanner.availability.displayMessage
    }

    /// 触发一次重建（scope 非 nil 时先按范围清理），回执回到主线程
    func rebuild(scope: HarnessRebuildScope?,
                 completion: @escaping @MainActor (HarnessRebuildReceipt?) -> Void) {
        harness.rebuildIndex(scope: scope) { receipt in
            Task { @MainActor in completion(receipt) }
        }
    }

    /// 清理前的规模预览（选择范围时调用，让确认框能写出「将删除 N 条」）
    ///
    /// 走仓储而不是门面服务：预览是「按同一套范围判据查一次计数」的纯读，
    /// 服务层没有必要再开一道口子（范围 → 起点毫秒的口径仍在 Core 的 purgeSinceMs）。
    func purgePreview(scope: HarnessRebuildScope) -> Int {
        store.harnessPurgePreview(scope: scope, now: Date())
    }

    // MARK: - 来源清单

    /// 单个来源在设置页里的一行读数
    struct SourceReading {
        let source: TokenSourceID
        /// 当前生效的目录（显式偏好 > 各来源默认推导）
        let path: String
        let enabled: Bool
        let status: TokenSourceStatus
        let sessionCount: Int
        let eventCount: Int
        /// 行副标题里的规模文案（没有数据时为 nil，不写「0 会话」）
        let countsText: String?
    }

    /// 一次读全所有来源（设置页刷新按行取用，避免每行各查一次库）
    func sourceReadings() -> [SourceReading] {
        let snapshot = harness.snapshot()
        let counts = sourceCounts()
        return TokenSourceID.allCases.map { source in
            // 目录口径：显式偏好 > 该来源的默认推导（环境变量优先，其次 home 下固定位置）
            let path = TokenSourcePreferences.rootPath(source, storage: storage)
                ?? source.defaultRoots().first?.path ?? ""
            let exists = !path.isEmpty && FileManager.default.fileExists(atPath: path)
            let readable = exists && FileManager.default.isReadableFile(atPath: path)
            let count = counts.first { $0.source == source }
            let sessions = count?.sessionCount ?? snapshot.bySource[source]?.sessionCount ?? 0
            let usage = snapshot.bySource[source]?.usage ?? .zero
            let status = TokenSourceStatusText.status(directoryExists: exists,
                                                     readable: readable,
                                                     sessionCount: sessions,
                                                     hasUsage: !usage.isZero)
            return SourceReading(source: source,
                                 path: path,
                                 enabled: TokenSourcePreferences.isEnabled(source, storage: storage),
                                 status: status,
                                 sessionCount: sessions,
                                 eventCount: count?.eventCount ?? 0,
                                 countsText: countsText(sessions: sessions, events: count?.eventCount ?? 0))
        }
    }

    /// 按来源的索引规模（仓储聚合；桩实现返回空 = 没有数据，不是错误）
    func sourceCounts() -> [HarnessSourceIndexCount] { store.harnessSourceCounts() }

    /// 行副标题的规模文案：有会话才写，事件数为 0 时不写「0 事件」
    private func countsText(sessions: Int, events: Int) -> String? {
        guard sessions > 0 || events > 0 else { return nil }
        let sessionText = String(sessions) + " 会话"
        guard events > 0 else { return sessionText }
        return sessionText + " / " + String(events) + " 事件"
    }

    /// 目录是否指向一个真实存在的目录（选择时就地校验，避免选完才发现是文件）
    static func isValidDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}