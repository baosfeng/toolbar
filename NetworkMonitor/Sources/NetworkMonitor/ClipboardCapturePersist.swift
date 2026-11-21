import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 应用协调器（采集落库编排）

/// 采集回调的落库编排 — 从剪贴板主装配拆出（主装配的族合计是棘轮）
///
/// 顺序固定：落库 → 交给识别（后台，不阻塞）→ 广播刷新 → 超限清理 + 图片回收。
/// 死锁红线：仓储方法在串行队列 sync，须在主线程调用；禁止在 db.query(sql:handler:) 回调内调用。
/// 跨文件访问：`database` / `clipboardPreferences` / `logger` 由主文件放宽为 internal。
extension AppCoordinator {

    /// 采集回调：落库 + 识别入队 + 广播 + 超限清理
    func persistClipboardDraft(_ draft: ClipboardDraft) {
        guard let repository = database else { return }
        guard let saved = repository.saveClipboardItem(draft) else {
            logger.warning("剪贴板条目落库失败（数据库未就绪或内容无效）")
            return
        }
        // 识别走后台、不阻塞采集主路径：不满足条件时调度器自己静默跳过
        enqueueClipboardOCR(for: saved)
        AppEvents.postClipboardChanged()
        // 超限清理（先按条数、再按容量，同一条执行路径）后回收被删条目的落盘图片；
        // 文本条目零 IO，见 ClipboardImageGC。真删了东西才补发事件：面板已经收过上面那条，
        // 这条只负责让「被清理掉的条目」从面板上消失，别在没删时多刷一次。
        let removed = ClipboardImageGC.prune(repository: repository,
                                            maxItems: clipboardPreferences.maxItems,
                                            retentionDays: clipboardPreferences.retentionDays,
                                            maxBytes: clipboardPreferences.maxBytes,
                                            logger: logger)
        if removed > 0 { AppEvents.postClipboardChanged() }
    }

    /// 采集状态变化：权限被拒时明确告警（不静默）
    func handleCaptureState(_ state: ClipboardCaptureState) {
        switch state {
        case .running:
            logger.info("剪贴板采集运行中")
        case .stopped:
            logger.info("剪贴板采集未运行（按需采集模式或已停止）")
        case .paused:
            logger.info("剪贴板采集已暂停（复制的内容不再入库）")
        case .denied(let reason):
            logger.warning("剪贴板访问被拒绝（\(reason.rawValue)）：请到「系统设置 → 隐私与安全性」允许本应用访问剪贴板")
        }
    }
}
