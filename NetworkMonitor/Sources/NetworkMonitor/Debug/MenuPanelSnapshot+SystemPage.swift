#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 系统页取证装配（拆出 MenuPanelSnapshot.swift）

/// 系统页快照装配 — 从主文件拆出（主文件贴近单文件 15 KiB 上限）
///
/// 取证态由 `NM_SNAPSHOT_SYSTEM_MODE` 控制：
/// - `full`（默认）：完整示意快照 + 全量历史（含 CPU 双序列 / 磁盘 IOPS / 负载三线）
/// - `empty`：快照与历史都不注入，验证「逐卡显示 —」的空态
/// - `nogpu`：GPU 为 nil 的降级态
/// - `pressure`：内存压力 = 紧张，验证四段条的内描边
/// - `load`：高负载态（三线远超核数、thermalState = critical）
/// - `battery`：电池降级态（电量 nil 但 AC / 循环次数仍有值）
/// - `noproc`：进程榜不可得（首帧差分缺失的场景）
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
            case "nogpu":
                snapshot = SnapshotFixtures.systemSnapshot(gpu: nil)
            case "pressure":
                snapshot = SnapshotFixtures.systemSnapshot(pressure: .critical)
            case "load":
                snapshot = SnapshotFixtures.systemSnapshot(load: SnapshotFixtures.highLoadSnapshot())
            case "battery":
                // 电量不可得但 AC / 循环次数可读：验证状态带不会整体消失，也不会写 0 冒充
                snapshot = SnapshotFixtures.systemSnapshot(
                    battery: BatterySnapshot(isOnAC: true, cycleCount: 89))
            case "noproc":
                snapshot = SnapshotFixtures.systemSnapshot(showsProcesses: false)
            default:
                snapshot = SnapshotFixtures.systemSnapshot()
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
                                             diskWriteIOPS: histories.diskWriteIOPS,
                                             loadShort: histories.loadShort,
                                             loadMedium: histories.loadMedium,
                                             loadLong: histories.loadLong)
            // 与示意快照的繁忙度（0.12）对齐：界面只写当前值，峰值只是 toolTip 里的口径补充
            panel.systemPane.updateDiskBusyTip(busyPeakPercent: 12)
        }
        // 与线上链路一致：按 Core 偏好默认值应用状态带温度段显隐（与空态无关）
        let showsThermal = SystemMonitorPreferences().isPanelItemVisible(.thermal)
        panel.systemPane.setShowsThermalCard(showsThermal)
        AppContext.shared.logger.info("系统页取证态：\(mode)，温度段偏好：\(showsThermal)")
    }
}
#endif
