#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 系统页取证装配（拆出 MenuPanelSnapshot.swift）

/// 系统页快照装配 — 从主文件拆出（主文件贴近单文件 15 KiB 上限）
///
/// 取证态由 `NM_SNAPSHOT_SYSTEM_MODE` 控制：
/// - `full`（默认）：完整示意快照 + 全量历史（含 CPU 双序列 / 磁盘 IOPS）
/// - `empty`：快照与历史都不注入，验证「逐卡显示 —」的空态
/// - `nogpu`：GPU 为 nil 的降级态
/// - `pressure`：内存压力 = 紧张，验证四段条的内描边
@MainActor
extension MenuPanelSnapshot {

    /// 把系统页示意数据（快照 + 历史 + 卡显隐）装进面板
    ///
    /// 空态必须连历史一起跳过：真实链路在没有 snapshot 时不会累积 history
    /// （见 MenuPanelController.systemTick），若这里仍灌历史，就会出现
    /// 「数值全是 —、曲线却画着」的假空态，把验收带偏。
    static func applySystemPage(to panel: MenuPanelView) {
        let mode = ProcessInfo.processInfo.environment["NM_SNAPSHOT_SYSTEM_MODE"] ?? "full"
        if mode != "empty" {
            let snapshot: SystemMetricsSnapshot
            switch mode {
            case "nogpu": snapshot = SnapshotFixtures.systemSnapshot(gpu: nil)
            case "pressure": snapshot = SnapshotFixtures.systemSnapshot(pressure: .critical)
            default: snapshot = SnapshotFixtures.systemSnapshot()
            }
            panel.updateSystem(snapshot, notifySize: false)
            let histories = SnapshotFixtures.systemHistories()
            panel.systemPane.updateHistories(cpu: histories.cpu,
                                             cpuSystem: histories.cpuSystem,
                                             gpu: histories.gpu,
                                             memory: histories.memory,
                                             diskRead: histories.diskRead,
                                             diskWrite: histories.diskWrite,
                                             diskReadIOPS: histories.diskReadIOPS,
                                             diskWriteIOPS: histories.diskWriteIOPS)
            // 与示意快照的繁忙度（0.12）对齐：界面只写当前值，峰值只是 toolTip 里的口径补充
            panel.systemPane.updateDiskBusyTip(busyPeakPercent: 12)
        }
        // 与线上链路一致：按 Core 偏好默认值应用温度卡显隐（验证默认即 6 卡；与空态无关）
        let showsThermal = SystemMonitorPreferences().isPanelItemVisible(.thermal)
        panel.systemPane.setShowsThermalCard(showsThermal)
        AppContext.shared.logger.info("系统页取证态：\(mode)，温度卡偏好：\(showsThermal)")
    }
}
#endif
