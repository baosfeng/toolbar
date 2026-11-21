import Foundation
import NetworkMonitorCore

// MARK: - 图片磁盘回收入口

/// 剪贴板图片磁盘回收 —— App 层唯一入口（仓储删除之后调用）
///
/// 三条硬约束：
/// 1. 只有 `kind == .image` 的条目会碰文件系统：大量文本条目时零 IO
/// 2. 每个文件的删除各自 do/catch，失败只 `logger.warning`，不回滚 DB、不抛给 UI
/// 3. 孤儿清扫只在启动后跑一次，不在采集 / 轮询路径上
public enum ClipboardImageGC {

    /// 回收一次删除操作涉及的图片文件
    /// - Parameters:
    ///   - items: 仓储删除接口返回的被删条目
    ///   - logger: 日志
    /// - Returns: 实际删除的文件数
    @discardableResult
    public static func reclaim(items: [ClipboardItem], logger: LoggingService) -> Int {
        let images = items.filter { $0.isImage }
        guard !images.isEmpty else { return 0 }
        // 同哈希换扩展名只在「记录仍存在」时才需要保留副本；记录已删则整组回收
        var removed = 0
        for item in images {
            removed += ClipboardImageStore.remove(imagePath: item.imagePath,
                                                 contentHash: item.contentHash,
                                                 logger: logger)
        }
        if removed > 0 {
            logger.debug("剪贴板图片回收完成：删除 \(removed) 个文件（对应 \(images.count) 条记录）")
        }
        return removed
    }


    // MARK: - 仓储删除 + 回收（调用方只走这三条，避免各自漏回收）

    /// 删除单条并回收其图片
    @discardableResult
    public static func delete(repository: any ClipboardRepository, id: UUID, logger: LoggingService) -> Bool {
        let doomed = repository.deleteClipboardItem(id: id)
        guard let doomed else { return false }
        reclaim(items: [doomed], logger: logger)
        return true
    }

    /// 清空历史（保留收藏）并回收被删条目的图片
    /// - Returns: 实际删除条数
    @discardableResult
    public static func clear(repository: any ClipboardRepository, keepingPinned: Bool,
                      logger: LoggingService) -> Int {
        let removed = repository.clearClipboardItems(keepingPinned: keepingPinned)
        reclaim(items: removed, logger: logger)
        return removed.count
    }

    /// 超限清理并回收被删条目的图片 —— **按条数与按容量走同一条执行路径**
    ///
    /// 顺序：先按条数（含保留天数）再按容量。理由：条数清理是既有的、语义最直接的一步，
    /// 它先把「条数已经超了」的条目删掉；随后容量清理只需在**剩下的**条目上从最旧往新删，
    /// 不会出现「容量先删一批、条数清理再删一批」两轮各自回收文件的重复 IO。
    /// 两条路径都走仓储删除 → 统一 `reclaim`，不存在第二套删文件逻辑。
    ///
    /// - Returns: 实际删除条数（两轮合计）
    @discardableResult
    public static func prune(repository: any ClipboardRepository, maxItems: Int, retentionDays: Int,
                      maxBytes: UInt64 = ClipboardCapacityUsage.unlimited,
                      logger: LoggingService) -> Int {
        let outcome = ClipboardLimitPruner.prune(repository: repository,
                                                maxItems: maxItems, retentionDays: retentionDays,
                                                maxBytes: maxBytes,
                                                imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:))
        guard !outcome.isEmpty else { return 0 }
        // 两轮合并成一次回收：reclaim 内部要列举目录，分两次等于把目录扫两遍
        reclaim(items: outcome.removed, logger: logger)
        if !outcome.byCapacity.isEmpty {
            logger.info("剪贴板容量超限清理：删除 \(outcome.byCapacity.count) 条（上限 \(maxBytes) 字节）")
        }
        return outcome.removedCount
    }

    /// 只做容量超限清理（启动清理入口用它，避免在冷启动上重跑按条数 / 保留天数两项）
    /// - Returns: 实际删除条数
    @discardableResult
    public static func pruneOverCapacity(repository: any ClipboardRepository, maxBytes: UInt64,
                                  logger: LoggingService) -> Int {
        let byBytes = ClipboardLimitPruner.pruneOverCapacity(
            repository: repository, maxBytes: maxBytes,
            imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:))
        guard !byBytes.isEmpty else { return 0 }
        reclaim(items: byBytes, logger: logger)
        logger.info("剪贴板容量超限清理：删除 \(byBytes.count) 条（上限 \(maxBytes) 字节）")
        return byBytes.count
    }

    /// 当前剪贴板总占用字节（正文 + 图片原图；口径见 `ClipboardCapacityUsage`）
    public static func capacityBytes(repository: any ClipboardRepository) -> UInt64 {
        guard let capacity = repository as? any ClipboardCapacityPruneRepository else { return 0 }
        return capacity.clipboardCapacityBytes(imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:))
    }

    /// 启动后一次清理：先按容量超限清理，再做孤儿清扫（延迟执行，避开启动期 IO 高峰）
    ///
    /// 为什么启动只清容量、不重跑按条数 / 保留天数：那两项在每次写入后都已持续兜住，
    /// 启动时再跑一遍只会在冷启动路径上多一次全表删除；容量则可能因为「上限刚被调小」
    /// 或上次会话异常退出而没来得及清，属于启动时必须补一次的那一类。
    ///
    /// 清理后若真的删了条目，发一次 `AppEvents.clipboardChanged`，面板按既有约定立即重读。
    ///
    /// - Parameters:
    ///   - repository: 用于取全量存活记录并执行容量清理
    ///   - maxBytes: 容量上限（0 = 不限）
    ///   - logger: 日志
    ///   - delay: 延迟秒数（≤ 0 立即执行）
    public static func sweepOrphansAfterLaunch(repository: any ClipboardRepository,
                                        maxBytes: UInt64 = ClipboardCapacityUsage.unlimited,
                                        logger: LoggingService,
                                        delay: TimeInterval = 5) {
        let sweep = { [logger] in
            // 容量清理在前：被删条目的原图由 pruneOverCapacity 内部回收，随后的孤儿清扫兜底
            if pruneOverCapacity(repository: repository, maxBytes: maxBytes, logger: logger) > 0 {
                AppEvents.postClipboardChanged()
            }
            let items = repository.fetchAllClipboardItems(kind: nil)
            let keptPaths = Set(items.compactMap(\.imagePath))
            let keptHashes = Set(items.map(\.contentHash))
            let removed = ClipboardImageStore.sweepOrphans(knownImagePaths: keptPaths,
                                                          knownContentHashes: keptHashes,
                                                          logger: logger)
            if removed > 0 {
                logger.info("剪贴板图片孤儿清扫完成：删除 \(removed) 个无引用文件")
            }
        }
        guard delay > 0 else { return sweep() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sweep() }
    }
}
