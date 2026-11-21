import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 应用协调器（剪贴板设置页回调）

/// 剪贴板设置页的动作实现 — 从 `AppCoordinator.swift` 拆出（主文件曾撑满 15 KiB）
///
/// 跨文件访问：`globalHotKey` / `clipboardWatcher` / `clipboardStack` / `clipboardPreferences` /
/// `clipboardPanel` / `database` 在主文件中放宽为 internal，仅供本扩展与装配流程使用。
extension AppCoordinator: ClipboardSettingsDelegate {

    /// 设置窗内重新录制快捷键：冲突时由设置窗标记冲突态，不再弹模态框
    func settingsDidChangeHotKey(_ combo: HotKeyCombo) -> Bool {
        registerClipboardHotKey(combo, presentingAlert: false)
    }

    /// 采集模式切换：按新模式重启采集器（分支 B 轮询 / 分支 A 按需）
    func settingsDidChangeCaptureMode() {
        clipboardWatcher.stop()
        clipboardWatcher.start()
        logger.info("剪贴板采集模式已切换为：\(clipboardPreferences.captureMode.label)")
    }

    /// 暂停 / 恢复：偏好由采集器这一处写，设置页只回读（两处都写会让「点两次」变成一次暂停一次恢复）
    func settingsDidChangePause(_ paused: Bool) {
        if paused { clipboardWatcher.pause() } else { clipboardWatcher.resume() }
        logger.info("剪贴板采集暂停更新：isPaused=\(clipboardWatcher.isPaused)")
    }

    /// 定时暂停：写截止时刻并进入暂停；到点由状态栏节拍自动恢复
    func settingsDidChangeTimedPause(until endDate: Date) {
        clipboardWatcher.pause(until: endDate)
        let minutes = ClipboardPauseLogic.remainingMinutes(pausedUntil: endDate, now: Date())
        logger.info("剪贴板定时暂停已生效：剩余 \(minutes) 分钟")
    }

    func settingsDidChangeIgnoredApps() {
        logger.info("剪贴板忽略应用已更新，共 \(clipboardPreferences.ignoredBundleIDs.count) 项")
    }

    // MARK: 图片存储

    /// 图片目录当前占用（设置页每次刷新现算，不缓存）
    func settingsClipboardImageUsage() -> ClipboardStorageUsage.Summary {
        ClipboardImageStore.usage
    }

    /// 最大容量变更：立即按新上限清一次，删了东西就发事件让面板刷新
    func settingsDidChangeMaxBytes() {
        guard let repository = database else { return }
        let removed = ClipboardImageGC.pruneOverCapacity(repository: repository,
                                                         maxBytes: clipboardPreferences.maxBytes,
                                                         logger: logger)
        guard removed > 0 else { return }
        AppEvents.postClipboardChanged()
        logger.info("剪贴板最大容量调整为 \(clipboardPreferences.maxBytes) 字节，已清理 \(removed) 条历史")
    }

    /// 剪贴板历史总占用（正文 + 图片原图，缩略图不计；与自动清理同一份口径）
    func settingsClipboardTotalUsageBytes() -> UInt64 {
        guard let repository = database else { return 0 }
        return ClipboardImageGC.capacityBytes(repository: repository)
    }

    /// 清空图片存储：复用既有「清空历史（保留收藏）」+ 孤儿清扫，不新写删除逻辑
    ///
    /// 先清历史让引用失效，再按存活记录做一次孤儿清扫——两步都是既有实现，
    /// 顺序反过来会把仍被收藏条目引用的原图当孤儿删掉（收藏条目的图片必须留着）。
    func settingsDidRequestClearImageStorage() -> ClipboardStorageCleanupResult {
        guard let repository = database else {
            // 失败不能落成「本来就没有可清空的」：error 级别让日志里能查到真因
            logger.error("清空图片存储失败：数据库未就绪，本次未执行任何删除")
            return ClipboardStorageCleanupResult(deletedItems: 0, removedFiles: 0)
        }
        let deletedItems = ClipboardImageGC.clear(repository: repository, keepingPinned: true, logger: logger)
        let kept = repository.fetchAllClipboardItems(kind: nil)
        let removedFiles = ClipboardImageStore.sweepOrphans(knownImagePaths: Set(kept.compactMap(\.imagePath)),
                                                           knownContentHashes: Set(kept.map(\.contentHash)),
                                                           logger: logger)
        // 历史被清空后，Paste Stack 里那些已被删掉的 id 必须同步掉出队列，
        // 否则面板仍显示「堆叠 N 条」，粘贴时队首却取不到内容、整条队列空转
        clipboardStack?.reloadStack()
        AppEvents.postClipboardChanged()
        logger.info("图片存储已清空：删除 \(deletedItems) 条历史、\(removedFiles) 个残留文件（收藏图片保留）")
        return ClipboardStorageCleanupResult(deletedItems: deletedItems, removedFiles: removedFiles)
    }

}
