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
///
/// Wi-Fi 链路态由 `NM_SNAPSHOT_WIFI_MODE` 独立控制（与上面几个系统态正交）：
/// - 缺省：给出贴近本机实测的链路（-65 / ch36 / 5GHz / 103 Mbps），用于核对正常态排版；
/// - `off`：强制 `wifi = nil`，用于取证「无接口 / 关闭 / 未连接」时整条显示「—」
///   而不是 0 dBm / 「极佳」的降级行为。
@MainActor
extension MenuPanelSnapshot {

    /// 把系统页示意数据（快照 + 历史 + 卡显隐）装进面板
    ///
    /// 空态必须连历史一起跳过：真实链路在没有 snapshot 时不会累积 history
    /// （见 MenuPanelController.systemTick），若这里仍灌历史，就会出现
    /// 「数值全是 —、曲线却画着」的假空态，把验收带偏。
    static func applySystemPage(to panel: MenuPanelView) {
        let mode = ProcessInfo.processInfo.environment["NM_SNAPSHOT_SYSTEM_MODE"] ?? "full"
        // Wi-Fi 降级取证：off → 强制 nil，验证「—」而不是 0 dBm
        let wifi = SnapshotFixtures.snapshotWiFi()
        let wifiOff = wifi == nil
        if mode != "empty" {
            let snapshot: SystemMetricsSnapshot
            switch mode {
            case "nogpu":
                snapshot = SnapshotFixtures.systemSnapshot(gpu: nil, wifi: wifi)
            case "pressure":
                snapshot = SnapshotFixtures.systemSnapshot(pressure: .critical, wifi: wifi)
            case "load":
                snapshot = SnapshotFixtures.systemSnapshot(load: SnapshotFixtures.highLoadSnapshot(),
                                                           wifi: wifi)
            case "battery":
                // 电量不可得但 AC / 循环次数可读：验证状态带不会整体消失，也不会写 0 冒充
                snapshot = SnapshotFixtures.systemSnapshot(
                    battery: BatterySnapshot(isOnAC: true, cycleCount: 89), wifi: wifi)
            case "noproc":
                snapshot = SnapshotFixtures.systemSnapshot(showsProcesses: false, wifi: wifi)
            default:
                snapshot = SnapshotFixtures.systemSnapshot(wifi: wifi)
            }
            panel.updateSystem(snapshot, notifySize: false)
            let histories = SnapshotFixtures.systemHistories()
            panel.systemPane.updateHistories(cpu: histories.cpu,
                                             cpuSystem: histories.cpuSystem,
                                             gpu: histories.gpu,
                                             memory: histories.memory,
                                             memoryWired: histories.memoryWired,
                                             memoryActive: histories.memoryActive,
                                             memoryCompressed: histories.memoryCompressed,
                                             diskRead: histories.diskRead,
                                             diskWrite: histories.diskWrite,
                                             loadShort: histories.loadShort,
                                             loadMedium: histories.loadMedium,
                                             loadLong: histories.loadLong)
            // 与示意快照的繁忙度（0.12）对齐：界面只写当前值，峰值只是 toolTip 里的口径补充
            panel.systemPane.updateDiskBusyTip(busyPeakPercent: 12)
        }
        // 与线上链路一致：按 Core 偏好默认值应用状态带温度段显隐（与空态无关）
        let preferences = SystemMonitorPreferences()
        let showsThermal = preferences.isPanelItemVisible(.thermal)
        panel.systemPane.setShowsThermalCard(showsThermal)
        // 与线上链路一致：采样周期取偏好真实值（详情页「采样」行不硬编码 1 秒）
        panel.systemPane.updateSampleInterval(preferences.sampleInterval)
        AppContext.shared.logger.info("系统页取证态：\(mode)，Wi-Fi 态：\(wifiOff ? "off" : "normal")，温度段偏好：\(showsThermal)")
    }

    /// 五个二级详情页取证 — menu-system-detail-{cpu,gpu,mem,disk,proc}-{light,dark}.png
    ///
    /// 每页都重新装配面板（同一份示意快照 + 全量历史），进入详情页后再量高度：
    /// 高度随页面内容变化，必须按详情页实际内容重算画布，不能沿用首屏高度。
    static func captureSystemDetails(directory: URL, items: [ClipboardItem]) {
        let pages: [(SystemPaneView.DetailPage, String)] = [
            (.cpu, "cpu"), (.gpu, "gpu"), (.memory, "mem"), (.disk, "disk"), (.process, "proc"),
        ]
        for (page, name) in pages {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let panel = makeMenuPanel(tab: .system, items: items)
                panel.systemPane.showDetail(page)
                let needed = panel.desiredContentHeight
                let height = min(max(needed, 180), MenuPanelStyle.maxHeight)
                let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
                let url = directory.appendingPathComponent("menu-system-detail-\(name)-\(suffix).png")
                render(view: panel, size: size, appearanceName: appearance, to: url)
            }
        }
    }
}
#endif
