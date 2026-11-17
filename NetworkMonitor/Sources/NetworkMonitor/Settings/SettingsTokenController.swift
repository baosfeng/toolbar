import AppKit
import NetworkMonitorCore

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
    private let storage: any KeyValueStorage
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

#if DEBUG
    /// 取证专用：同步查一次事件数（只给离屏快照用，运行期一律走异步 loadSummary）
    ///
    /// 离屏渲染是一次性的：不同步补这一笔，快照里「索引事件」永远停在「…」，
    /// 读图的人无法确认这行接得对不对。
    func debugEventCount() -> Int { store.harnessEventCount() }
#endif

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

    /// 目录是否指向一个真实存在的目录（选择时就地校验，避免选完才发现是文件）
    static func isValidDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
