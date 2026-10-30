import Foundation
import NetworkMonitorCore

// MARK: - 第二批 P0 指标断言（负载 / 进程 Top-N / GPU 功耗 / 电池）
//
// 拆出原因：SystemMetricsTests.swift（12.8 KB）与 ExtraTests（12.0 KB）都逼近
// 单文件 15360 字节上限；本文件覆盖第二批四项的口径与边界，
// 由 runSystemMetricsTests() 末尾调用，main.swift 调度顺序不变。

/// 负载归一化 + 进程 CPU% 时基换算（第二批 P0 前半）
///
/// 拆出原因：本组断言合起来会超过单文件 15360 字节门禁，故按主题分成两个文件；
/// 主入口 runSystemMetricsSupplementTests() 在本文件，末尾转调另一半。
func runSystemMetricsSupplementTests() {
    testNormalizedLoad()
    testProcessCPUPercent()
    runSystemMetricsProcessAndPowerTests()
}

// MARK: - 负载归一化

private func testNormalizedLoad() {
    // 正常：10 核机器 load1 = 2.5 → 0.25
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(2.5, coreCount: 10), 0.25,
                "2.5 / 10 核 = 0.25")
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(10, coreCount: 10), 1,
                "load 等于核数 = 1.0")

    // 正常：load 超过核数不封顶（排队越严重越该显眼）
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(20, coreCount: 10), 2,
                "过载时不封顶（2.0 表示 2 倍排队）")

    // 边界：核数 ≤ 0（取不到）→ nil，不猜分母
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(2.5, coreCount: 0), nil,
                "核数 0 返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(2.5, coreCount: -4), nil,
                "负核数返回 nil")

    // 异常：脏值不展示成 0
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(-1, coreCount: 10), nil,
                "负负载返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(.nan, coreCount: 10), nil,
                "NaN 返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(.infinity, coreCount: 10), nil,
                "无穷返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.normalizedLoad(0, coreCount: 10), 0,
                "0 负载是有效读数")
}

// MARK: - 进程 CPU%（时基换算）

private func testProcessCPUPercent() {
    // 正常：1 秒内 +7200 tick，1 tick = 41.6667 ns
    // 7200 × 41.6667ns = 300 µs? 不，7200 × 41.6667 = 300000 ns = 0.3 ms
    // 取能覆盖 100% 的量级：1 秒满单核 ≈ 24,000,000 tick
    let ticksPerSecondFullCore = UInt64(1_000_000_000 / 41.666666666666664)
    let single = SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0,
        currentTicks: ticksPerSecondFullCore,
        nanosecondsPerTick: 41.666666666666664,
        elapsedSeconds: 1)
    assertEqual(single.map { abs($0 - 100) < 0.001 }, true, "单核满载 ≈ 100%")

    // 关键反例：多线程进程合法超过 100%，不 clamp
    let three = SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0,
        currentTicks: ticksPerSecondFullCore * 3,
        nanosecondsPerTick: 41.666666666666664,
        elapsedSeconds: 1)
    assertEqual(three.map { abs($0 - 300) < 0.001 }, true, "3 线程满载 ≈ 300%（不 clamp 到 100）")

    // 时基口径：同一 raw delta 在 Intel（1 ns/tick）与 Apple Silicon（41.67 ns/tick）差 41.67 倍
    let rawDelta: UInt64 = 24_000_000
    let appleSilicon = SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0, currentTicks: rawDelta,
        nanosecondsPerTick: 41.666666666666664, elapsedSeconds: 1)
    let intel = SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0, currentTicks: rawDelta, nanosecondsPerTick: 1, elapsedSeconds: 1)
    assertEqual(intel.map { abs($0 - 2.4) < 0.001 }, true, "Intel timebase 1/1：24M tick = 2.4%")
    assertEqual(appleSilicon.map { abs($0 - 100) < 0.001 }, true,
                "Apple Silicon 125/3：同一 delta = 100%（差 41.67 倍）")

    // 边界：时间差 ≤ 0 返回 nil
    assertEqual(SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0, currentTicks: 1000,
        nanosecondsPerTick: 41.666666666666664, elapsedSeconds: 0), nil, "时间差 0 返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0, currentTicks: 1000,
        nanosecondsPerTick: 41.666666666666664, elapsedSeconds: -1), nil, "负时间差返回 nil")

    // 边界：timebase 非法（0 / 负 / 非有限）返回 nil
    assertEqual(SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0, currentTicks: 1000, nanosecondsPerTick: 0, elapsedSeconds: 1), nil,
        "timebase 0 返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 0, currentTicks: 1000, nanosecondsPerTick: .nan, elapsedSeconds: 1), nil,
        "timebase NaN 返回 nil")

    // 异常：累计值倒退（进程重置）→ nil，不返回负百分比
    assertEqual(SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 1000, currentTicks: 500,
        nanosecondsPerTick: 41.666666666666664, elapsedSeconds: 1), nil, "计数倒退返回 nil")

    // 边界：零增量是有效读数（进程确实没跑）
    assertEqual(SystemMetricsSupplementCalculations.cpuPercent(
        previousTicks: 500, currentTicks: 500,
        nanosecondsPerTick: 41.666666666666664, elapsedSeconds: 1), 0, "零增量 → 0%")
}


