import Foundation
import NetworkMonitorCore

// MARK: - 进程榜口径（CPU 榜 / 内存榜）

/// 进程榜切换 / 排序 / 条形刻度 / 数值文本 — 首屏 Top-2 与「压力详情」Top-10 共用
func runSystemProcessBoardTests() {
    print("\n🧪 Testing SystemProcessBoard...")
    testBoardSelection()
    testBoardBarFractions()
    testBoardValueTexts()
}

// MARK: - 榜单选择与排序

private func testBoardSelection() {
    // 采样层已按两个维度各排好一份；这里只验证「选哪份 + 截断」
    let cpuBoard = [
        ProcessResourceUsage(pid: 1, name: "alpha", cpuPercent: 100, residentBytes: 1_000_000),
        ProcessResourceUsage(pid: 3, name: "gamma", cpuPercent: 50, residentBytes: 3_000_000),
        ProcessResourceUsage(pid: 2, name: "beta", cpuPercent: 10, residentBytes: 9_000_000),
    ]
    let memoryBoard = [
        ProcessResourceUsage(pid: 2, name: "beta", cpuPercent: 10, residentBytes: 9_000_000),
        ProcessResourceUsage(pid: 3, name: "gamma", cpuPercent: 50, residentBytes: 3_000_000),
        ProcessResourceUsage(pid: 1, name: "alpha", cpuPercent: 100, residentBytes: 1_000_000),
    ]
    let snapshot = ProcessResourceSnapshot(topCPU: cpuBoard, topMemory: memoryBoard,
                                           scannedCount: 512)

    // CPU 榜：按 CPU 降序、Top-2 截断
    assertEqual(SystemProcessBoard.rows(snapshot, metric: .cpu, limit: 2).map(\.pid), [1, 3],
                "CPU 榜取前 2（alpha / gamma）")
    // 内存榜：按内存降序（与 CPU 榜顺序不同，证明切换真的换了排序来源）
    assertEqual(SystemProcessBoard.rows(snapshot, metric: .memory, limit: 2).map(\.pid), [2, 3],
                "内存榜取前 2（beta / gamma）")
    // 详情页 Top-10：不足 10 条按实际条数
    assertEqual(SystemProcessBoard.rows(snapshot, metric: .cpu, limit: 10).count, 3,
                "Top-10 不足时按实际条数")

    // 边界 / 异常
    assertEqual(SystemProcessBoard.rows(nil, metric: .cpu, limit: 10).isEmpty, true,
                "快照 nil（首帧无基线）→ 空榜单")
    assertEqual(SystemProcessBoard.rows(snapshot, metric: .cpu, limit: 0).isEmpty, true,
                "limit 0 → 空榜单")
    assertEqual(SystemProcessBoard.rows(snapshot, metric: .memory, limit: -1).isEmpty, true,
                "limit 负数 → 空榜单")
}

// MARK: - 条形刻度

private func testBoardBarFractions() {
    // CPU 榜：sqrt 绝对刻度，k = 13
    assertEqual(abs(SystemProcessBoard.cpuBarFraction(27.6) - 0.683) < 0.001, true,
                "27.6% → 68.3% 条长")
    assertEqual(SystemProcessBoard.cpuBarFraction(100), 1, "满条 = 占满一个核，且封顶 1")
    assertEqual(SystemProcessBoard.cpuBarFraction(0), 0, "0% → 空条")
    assertEqual(SystemProcessBoard.cpuBarFraction(.nan), 0, "NaN → 0")
    assertEqual(SystemProcessBoard.cpuBarFraction(-5), 0, "负值 → 0")

    // 内存榜：常驻 / 物理内存 线性
    assertEqual(SystemProcessBoard.memoryBarFraction(residentBytes: 8_000, totalBytes: 16_000), 0.5,
                "8 GB / 16 GB = 50%")
    assertEqual(SystemProcessBoard.memoryBarFraction(residentBytes: 8_000, totalBytes: 0), 0,
                "总量 0 不产生除零")
    assertEqual(SystemProcessBoard.memoryBarFraction(residentBytes: 20_000, totalBytes: 16_000), 1,
                "超过物理内存封顶 1")

    // 单条按维度取刻度
    let usage = ProcessResourceUsage(pid: 1, name: "alpha", cpuPercent: 25,
                                     residentBytes: 8_000)
    assertEqual(abs(SystemProcessBoard.barFraction(for: usage, metric: .cpu, memoryTotal: 16_000)
                    - SystemProcessBoard.cpuBarFraction(25)) < 0.000_001, true,
                "单条 CPU 刻度与整榜同式")
    assertEqual(SystemProcessBoard.barFraction(for: usage, metric: .memory, memoryTotal: 16_000),
                0.5, "单条内存刻度 = 常驻 / 物理内存")
    assertEqual(SystemProcessBoard.barFraction(for: usage, metric: .memory, memoryTotal: nil), 0,
                "物理内存不可得时内存榜条形为 0")
}

// MARK: - 数值文本

private func testBoardValueTexts() {
    assertEqual(SystemProcessBoard.cpuValueText(15.77), "15.8%", "CPU 原值 1 位小数")
    assertEqual(SystemProcessBoard.cpuValueText(298.4), "298.4%", "多线程 >100% 不 clamp")
    assertEqual(SystemProcessBoard.cpuValueText(.nan), "—", "NaN 显示「—」")
    assertEqual(SystemProcessBoard.cpuValueText(-3), "0.0%", "负值归 0")

    assertEqual(SystemProcessBoard.formatBytes(0), "0 B", "0 字节")
    assertEqual(SystemProcessBoard.formatBytes(512), "512 B", "B 级取整")
    assertEqual(SystemProcessBoard.formatBytes(1_536), "1.5 KB", "KB 级 1 位小数")
    assertEqual(SystemProcessBoard.formatBytes(1_048_576), "1.0 MB", "MB 级")

    let memoryUsage = ProcessResourceUsage(pid: 2, name: "beta", cpuPercent: 10,
                                           residentBytes: 1_048_576)
    assertEqual(SystemProcessBoard.valueText(for: memoryUsage, metric: .memory), "1.0 MB",
                "内存榜数值带单位")
    assertEqual(SystemProcessBoard.valueText(for: memoryUsage, metric: .cpu), "10.0%",
                "CPU 榜数值是百分比")
}
