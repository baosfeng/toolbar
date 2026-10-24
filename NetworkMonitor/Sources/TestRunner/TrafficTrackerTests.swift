import Foundation
import NetworkMonitorCore

// MARK: - 每日流量追踪（从 main.swift 拆出）

// MARK: - TrafficTracker 每日流量

func runTrafficTrackerTests() {
    print("\n🧪 Testing TrafficTracker...")

    do {
        // 模拟网络监控（累计值可变）
        final class MockMonitor: NetworkMonitoringService {
            var downloadSpeed: Double = 0
            var uploadSpeed: Double = 0
            var totalRx: UInt64
            var totalTx: UInt64

            init(totalRx: UInt64, totalTx: UInt64) {
                self.totalRx = totalRx
                self.totalTx = totalTx
            }

            func poll() {}
        }

        let suite = UserDefaults(suiteName: "test.traffic-\(UUID().uuidString)")!
        let monitor = MockMonitor(totalRx: 1000, totalTx: 500)
        let tracker = TrafficTracker(
            monitor: monitor,
            storage: UserDefaultsStorage(defaults: suite)
        )

        // 启动基准入库：累计值未变 → 今日流量 0
        assertEqual(tracker.todayRx, 0, "initial todayRx zero")
        assertEqual(tracker.todayTx, 0, "initial todayTx zero")

        // 累计增加 2.5MB / 1MB → 今日流量等于增量
        monitor.totalRx = 1_000 + 2_500_000
        monitor.totalTx = 500 + 1_000_000
        assertEqual(tracker.todayRx, 2_500_000, "todayRx equals increment")
        assertEqual(tracker.todayTx, 1_000_000, "todayTx equals increment")

        // weekEntries：无日志时仅今天一条，label 为短日期格式
        let entries = tracker.weekEntries
        assertEqual(entries.count, 1, "weekEntries only today without log")
        assertEqual(entries[0].rx, 2_500_000, "weekEntries today rx")
        assertEqual(entries[0].label.contains("/"), true, "week label short format")

        // 当天 update() 不切换日期、无副作用
        tracker.update()
        assertEqual(tracker.todayRx, 2_500_000, "update keeps today rx")

        // 基准解析：累计回退（崩溃重启读到更旧值）时以当前累计重建，正常增长时沿用
        assertEqual(TrafficTracker.resolveBaseline(currentRx: 100, currentTx: 50,
                                                   storedRx: 1_000, storedTx: 500).rx, 100,
                    "baseline resets on rx regression")
        assertEqual(TrafficTracker.resolveBaseline(currentRx: 1_000, currentTx: 50,
                                                   storedRx: 1_000, storedTx: 500).tx, 50,
                    "baseline resets on tx regression")
        let kept = TrafficTracker.resolveBaseline(currentRx: 2_000, currentTx: 900,
                                                  storedRx: 1_000, storedTx: 500)
        assertEqual(kept.rx, 1_000, "baseline kept on rx growth")
        assertEqual(kept.tx, 500, "baseline kept on tx growth")

        // 端到端：存储基准大于当前累计 → 重建基准并落盘，之后增量恢复可见
        let suiteRegress = UserDefaults(suiteName: "test.traffic-regress-\(UUID().uuidString)")!
        let storageRegress = UserDefaultsStorage(defaults: suiteRegress)
        storageRegress.set(5_000, forKey: "dayStartRx")
        storageRegress.set(3_000, forKey: "dayStartTx")
        let monitorRegress = MockMonitor(totalRx: 1_000, totalTx: 500)
        let trackerRegress = TrafficTracker(monitor: monitorRegress, storage: storageRegress)
        assertEqual(trackerRegress.todayRx, 0, "regressed baseline shows zero today")
        assertEqual(storageRegress.integer(forKey: "dayStartRx"), 1_000,
                    "regressed baseline persisted")
        monitorRegress.totalRx = 1_500
        assertEqual(trackerRegress.todayRx, 500, "today rx counts after regression reset")

        print("✅ TrafficTracker 每日流量 works")
    }

}

