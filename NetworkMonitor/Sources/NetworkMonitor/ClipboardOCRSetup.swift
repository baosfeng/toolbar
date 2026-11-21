import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 应用协调器（图片文字识别装配）

/// 图片文字识别的装配与入队 — 与剪贴板主装配分开成文件
///
/// 理由：识别是「后台异步写」的链路，生命周期与采集 / 粘贴完全不同；
/// 主装配文件只留一行调用点，后续换识别实现（语言 / 档位 / 引擎）不必再动它。
/// 跨文件访问：`clipboardOCR` / `logger` 由主文件放宽为 internal。
extension AppCoordinator {

    /// 装配识别调度器并安排启动补扫
    func setupClipboardOCR(database: any AppDatabase, preferences: ClipboardPreferences) {
        let ocr = ClipboardOCRCoordinator(recognizer: VisionTextRecognizer(), repository: database,
                                          preferences: preferences, logger: logger)
        clipboardOCR = ocr
        schedulePendingOCRScan(ocr, repository: database)
    }

    /// 采集落库后把图片条目交给识别（后台跑，不阻塞采集主路径）
    func enqueueClipboardOCR(for item: ClipboardItem) {
        clipboardOCR?.schedule(item)
    }

    /// 启动补扫：上次退出时排到一半的图片条目重新入队
    ///
    /// 延迟 5 秒（与孤儿清扫同一节奏）：把识别让到启动首帧之后，不与首屏抢 CPU。
    /// 只扫当前历史里 `ocr_text` 为 NULL 的图片条目，条数由 maxItems 兜住。
    private func schedulePendingOCRScan(_ ocr: ClipboardOCRCoordinator, repository: any AppDatabase) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.clipboardOCR === ocr else { return }
            ocr.schedulePending(from: repository.fetchAllClipboardItems(kind: .image))
        }
    }
}
