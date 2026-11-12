import Foundation
import NetworkMonitorCore

// MARK: - 图片磁盘回收入口

/// 剪贴板图片磁盘回收 —— App 层唯一入口（仓储删除之后调用）
///
/// 三条硬约束：
/// 1. 只有 `kind == .image` 的条目会碰文件系统：大量文本条目时零 IO
/// 2. 每个文件的删除各自 do/catch，失败只 `logger.warning`，不回滚 DB、不抛给 UI
/// 3. 孤儿清扫只在启动后跑一次，不在采集 / 轮询路径上
enum ClipboardImageGC {

    /// 回收一次删除操作涉及的图片文件
    /// - Parameters:
    ///   - items: 仓储删除接口返回的被删条目
    ///   - logger: 日志
    /// - Returns: 实际删除的文件数
    @discardableResult
    static func reclaim(items: [ClipboardItem], logger: LoggingService) -> Int {
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
    static func delete(repository: any ClipboardRepository, id: UUID, logger: LoggingService) -> Bool {
        let doomed = repository.deleteClipboardItem(id: id)
        guard let doomed else { return false }
        reclaim(items: [doomed], logger: logger)
        return true
    }

    /// 清空历史（保留收藏）并回收被删条目的图片
    /// - Returns: 实际删除条数
    @discardableResult
    static func clear(repository: any ClipboardRepository, keepingPinned: Bool,
                      logger: LoggingService) -> Int {
        let removed = repository.clearClipboardItems(keepingPinned: keepingPinned)
        reclaim(items: removed, logger: logger)
        return removed.count
    }

    /// 超限清理并回收被删条目的图片
    /// - Returns: 实际删除条数
    @discardableResult
    static func prune(repository: any ClipboardRepository, maxItems: Int, retentionDays: Int,
                      logger: LoggingService) -> Int {
        let pruned = repository.pruneClipboardItems(maxItems: maxItems, retentionDays: retentionDays)
        reclaim(items: pruned, logger: logger)
        return pruned.count
    }

    /// 启动后一次孤儿清扫（延迟执行，避开启动期 IO 高峰）
    /// - Parameters:
    ///   - repository: 用于取全量存活记录
    ///   - logger: 日志
    ///   - delay: 延迟秒数（≤ 0 立即执行）
    static func sweepOrphansAfterLaunch(repository: any ClipboardRepository,
                                        logger: LoggingService,
                                        delay: TimeInterval = 5) {
        let sweep = { [logger] in
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
