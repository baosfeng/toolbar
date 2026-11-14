import AppKit
import NetworkMonitorCore

// MARK: - 面板操作反馈（音效 + 触觉）

/// 操作反馈接线 — 把控制器既有动作的成功 / 失败落到音效与触觉，不新增第二套动作实现
///
/// 口径（设计规格 §3 B3 / B4）：
/// - 选中切换 → 触觉 selection；
/// - 收藏切换 → 触觉 levelChange + 音效 pin（只在真正翻转收藏态时打一次）；
/// - 复制 → copy、粘贴 → paste、删除成功 → delete、失败 → error；
/// - 栈粘贴推进 → 触觉 levelChange。
///
/// 音效 / 触觉的实现每次调用现读偏好，这里不做开关判断，也不缓存状态。
/// 跨文件访问：`feedback` / `preferences` / `paster` / `logger` / `handleOutcome`
/// 由主文件放宽为 internal，仅供本扩展使用。
extension ClipboardPanelController {

    // MARK: 收藏

    /// 收藏态翻转（真翻转才响：同一态重复刷新不重复触发）
    func reportPinToggled(to pinned: Bool) {
        feedback.haptics.tap(.levelChange)
        feedback.sound.play(.pin)
        logger.debug("剪贴板收藏态切换：isPinned=\(pinned)")
    }

    // MARK: 复制 / 粘贴

    /// 复制结果反馈（copyOnly 走这里）：成功 -> copy，失败 -> error
    func reportCopyOutcome(_ outcome: ClipboardPasteOutcome) {
        if case .failed = outcome {
            feedback.sound.play(.error)
        } else {
            feedback.sound.play(.copy)
        }
        handleOutcome(outcome)
    }

    /// 粘贴结果反馈：成功 -> paste、降级为仅复制 -> copy、失败 -> error
    func reportPasteOutcome(_ outcome: ClipboardPasteOutcome) {
        switch outcome {
        case .pasted:                 feedback.sound.play(.paste)
        case .copiedOnly:             feedback.sound.play(.copy)
        case .failed:                 feedback.sound.play(.error)
        }
        handleOutcome(outcome)
    }

    /// 栈粘贴推进（队首被贴出、队列整体前移）
    func reportStackAdvanced() {
        feedback.haptics.tap(.levelChange)
    }
}
