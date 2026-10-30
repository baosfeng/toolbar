import AppKit
import NetworkMonitorCore

// MARK: - 菜单面板（系统页刷新，拆出 MenuPanelController.swift）

/// 系统页刷新链路 — 采样推进、60 点历史累积与 5 秒节流渲染
///
/// 采样服务由组合根注入（`any SystemMonitoringService`），面板只调 `poll()` 与读 `snapshot`，
/// 不感知具体采样实现；未装配时全部降级为空态（显示「—」）。
extension MenuPanelController {

    /// 系统页视图刷新间隔（秒）：与网络页中频刷新同一档
    static let systemRefreshInterval: TimeInterval = 5.0

    /// 每秒调用（面板展开时）：取快照推进历史，再按间隔节流渲染
    ///
    /// 历史只在面板展开期间累积：收起后曲线会出现断档，但避免后台长期占内存。
    func systemTick() {
        guard popover.isShown else { return }
        if let snapshot = systemMonitor?.snapshot {
            systemHistory.append(snapshot)
        }
        let now = Date()
        guard now.timeIntervalSince(lastSystemRefresh) >= Self.systemRefreshInterval else { return }
        lastSystemRefresh = now
        renderSystem()
    }

    /// 面板打开 / 切到系统页时的刷新（先采一帧由调用方决定，这里只渲染）
    func refreshSystem() {
        lastSystemRefresh = Date()
        renderSystem()
    }

    /// 把快照与历史推进到面板视图
    ///
    /// 历史按序列压缩：某一帧缺该项（如首帧 CPU 为 nil）就跳过该点，不影响其余序列。
    func renderSystem() {
        content.updateSystem(systemMonitor?.snapshot, notifySize: popover.isShown)
        // 两处必须同时改：这里少补一位，对应曲线就永远拿不到点（不显示、也不报错）
        let diskBusy = historyValues { $0.disk?.busyFraction }
        content.systemPane.updateHistories(
            cpu: historyValues { $0.cpu?.totalUsage },
            cpuSystem: historyValues { $0.cpu?.systemUsage },
            gpu: historyValues { $0.gpu?.utilization },
            memory: historyValues { snapshot in
                guard let memory = snapshot.memory, memory.total > 0 else { return nil }
                return Double(memory.used) / Double(memory.total)
            },
            diskRead: historyValues { $0.disk?.readBytesPerSecond },
            diskWrite: historyValues { $0.disk?.writeBytesPerSecond },
            diskReadIOPS: historyValues { $0.disk?.readIOPS },
            diskWriteIOPS: historyValues { $0.disk?.writeIOPS },
            loadShort: historyValues { $0.load?.load1 },
            loadMedium: historyValues { $0.load?.load5 },
            loadLong: historyValues { $0.load?.load15 }
        )
        content.systemPane.updateDiskBusyTip(busyPeakPercent: diskBusy.max().map {
            Int(($0 * 100).rounded())
        })
        // 温度段显隐由设置页开关驱动（v4 起温度卡已下线，开关语义变成
        // 「底部状态带里的温度是否显示」；偏好默认开启，取不到按 nil 降级）
        if let systemPreferences {
            content.systemPane.setShowsThermalCard(systemPreferences.isPanelItemVisible(.thermal))
        }
    }

    /// 历史中按取值闭包压缩出的序列（缺失项跳过）
    private func historyValues(_ extract: (SystemMetricsSnapshot) -> Double?) -> [Double] {
        systemHistory.values.compactMap(extract)
    }
}
