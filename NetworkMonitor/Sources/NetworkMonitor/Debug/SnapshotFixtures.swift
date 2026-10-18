#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 快照示意数据

/// 快照专用示意数据 — 折线 / 近 6 日柱状图 / 活跃进程
///
/// 拆到独立文件是为了让 `MenuPanelSnapshot.swift` 回到单文件体积上限（≤15 KiB）内。
/// 这些值只在 `NM_SNAPSHOT_DIR` 快照模式下使用，不参与生产逻辑。
enum SnapshotFixtures {

    /// 折线示意数据：正弦抖动，便于看出折线形状
    static func history(base: Double, amplitude: Double) -> [Double] {
        (0..<60).map { index in
            base + amplitude * (0.5 + 0.5 * sin(Double(index) / 4.0))
        }
    }

    /// 近 6 日柱状图示意数据（时间正序：最左最早、最右今天）
    static func dailyBars() -> [MenuPanelMetrics.DailyTrafficBar] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let values: [UInt64] = [3_100_000_000, 1_800_000_000, 4_200_000_000,
                                2_400_000_000, 5_600_000_000, 2_000_000_000]
        let calendar = Calendar.current
        return values.enumerated().map { offset, value in
            let day = calendar.date(byAdding: .day, value: offset - 5, to: Date()) ?? Date()
            return MenuPanelMetrics.DailyTrafficBar(label: formatter.string(from: day),
                                                    rx: value, tx: value / 5,
                                                    isToday: offset == values.count - 1)
        }
    }

    /// 活跃进程示意数据（进程名真实 → 可验证 NSWorkspace 真实图标解析）
    ///
    /// - Parameter count: 条数；超过 5 条时用于「内容高于 520pt」的可滚动自证
    static func processes(count: Int = 5) -> [ProcessNetUsage] {
        let names = ["Safari", "Google Chrome", "Terminal", "WeChat", "Spotify",
                     "Xcode", "Slack", "Notes", "Mail", "Finder", "Firefox", "Discord"]
        return (0..<max(0, count)).map { index in
            let name = names[index % names.count] + (index < names.count ? "" : " \(index + 1)")
            return ProcessNetUsage(name: name, pid: Int32(1200 + index),
                                   bytesIn: UInt64(1_200_000 / (index + 1)),
                                   bytesOut: UInt64(90_000 / (index + 1)))
        }
    }
}
#endif
