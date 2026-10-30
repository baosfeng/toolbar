import Foundation
import NetworkMonitorCore

// MARK: - 系统指标纯计算断言

/// 从采样器下沉到 Core 的三类纯计算：CPU 差分 / 磁盘速率 / GPU 降级判定
///
/// 采样器在 NetworkMonitor 目标（TestRunner 依赖不到），因此口径与边界全部在 Core 中可测。
/// 由 runSystemMetricsTests() 调用，保持 main.swift 的注册入口不变。
func runSystemMetricsCalculationTests() {
    testCPUCalculations()
    testDiskCalculations()
    testGPUCalculations()
}

// MARK: - CPU 差分

private func testCPUCalculations() {
    // 正常：核 0 全忙（+90 user / +10 system），核 1 全闲（+100 idle）
    let previous: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 0]
    let current: [UInt32] = [90, 10, 0, 0, 0, 0, 100, 0]
    guard let sample = SystemMetricsCalculations.cpuUsage(previous: previous, current: current) else {
        assertNotNil(nil as CPUUsageSample?, "CPU 差分应返回结果")
        return
    }
    assertEqual(sample.perCore.count, 2, "每核利用率按核数返回")
    assertEqual(sample.perCore[0], 1.0, "核 0 全忙 → 1.0")
    assertEqual(sample.perCore[1], 0.0, "核 1 全闲 → 0.0")
    assertEqual(sample.totalUsage, 0.5, "总利用率 = 100/200")
    assertEqual(sample.userUsage, 0.45, "user 占比 = 90/200")
    assertEqual(sample.systemUsage, 0.05, "system 占比 = 10/200")

    // 边界：零 delta（两帧完全相同）→ 全 0，不产生 NaN / Inf
    guard let zero = SystemMetricsCalculations.cpuUsage(previous: current, current: current) else {
        assertNotNil(nil as CPUUsageSample?, "零 delta 应返回结果")
        return
    }
    assertEqual(zero.perCore, [0, 0], "零 delta：每核全 0")
    assertEqual(zero.totalUsage, 0, "零 delta：总利用率 0")

    // 边界：核数变化 → 按最小核数截断
    let moreCores: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let truncated = SystemMetricsCalculations.cpuUsage(previous: previous, current: moreCores)
    assertEqual(truncated?.perCore.count, 2, "核数变化按最小核数截断")

    // 异常：倒退计数（计数器重置）按 0 处理，不产生负利用率
    let backwards = SystemMetricsCalculations.cpuUsage(previous: [10, 10, 10, 10],
                                                       current: [5, 5, 5, 5])
    assertEqual(backwards?.totalUsage, 0, "计数倒退按 0 处理")

    // 异常：空数组 / 长度不是 4 的倍数 → nil
    assertEqual(SystemMetricsCalculations.cpuUsage(previous: [], current: current), nil, "空数组返回 nil")
    assertEqual(SystemMetricsCalculations.cpuUsage(previous: [1, 2, 3], current: [4, 5, 6]), nil,
                "长度不是 4 的倍数返回 nil")
}

// MARK: - 磁盘速率

private func testDiskCalculations() {
    // 正常：1 秒内累计增加 2048 字节
    assertEqual(SystemMetricsCalculations.bytesPerSecond(previous: 1_024, current: 3_072, elapsed: 1), 2_048,
                "1 秒 +2048 字节 → 2048 B/s")
    assertEqual(SystemMetricsCalculations.bytesPerSecond(previous: 500, current: 500, elapsed: 2), 0,
                "累计不变 → 0 B/s")

    // 边界：时间差 ≤ 0 不除零
    assertEqual(SystemMetricsCalculations.bytesPerSecond(previous: 0, current: 100, elapsed: 0), nil,
                "时间差 0 返回 nil")
    assertEqual(SystemMetricsCalculations.bytesPerSecond(previous: 0, current: 100, elapsed: -1), nil,
                "负时间差返回 nil")

    // 边界：累计值倒退（换盘 / 重置）→ nil，不返回负速率
    assertEqual(SystemMetricsCalculations.bytesPerSecond(previous: 500, current: 100, elapsed: 1), nil,
                "累计值倒退返回 nil")

    // 边界：超大值不溢出
    let huge = UInt64.max / 2
    assertEqual(SystemMetricsCalculations.bytesPerSecond(previous: 0, current: huge, elapsed: 0.5),
                Double(huge) / 0.5, "超大累计值按 Double 换算不溢出")
}

// MARK: - GPU 降级判定

private func testGPUCalculations() {
    // 正常：键存在且为数字
    let valid: [String: Any] = ["Device Utilization %": 50, "Renderer Utilization %": 12]
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: valid, isWarm: true), 0.5,
                "Device 50% → 0.5")

    // 边界：预热首帧一律 nil（冷读的 0% 不可信）
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: valid, isWarm: false), nil,
                "预热首帧返回 nil")

    // 边界：空字典 / 缺键
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: [:], isWarm: true), nil,
                "空字典返回 nil")
    let missing: [String: Any] = ["Renderer Utilization %": 12]
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: missing, isWarm: true), nil,
                "缺 Device 键返回 nil")

    // 异常：值不是数字
    let nonNumeric: [String: Any] = ["Device Utilization %": "50"]
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: nonNumeric, isWarm: true), nil,
                "非数字值返回 nil")

    // 异常：越界（< 0 / > 100）
    let negative: [String: Any] = ["Device Utilization %": -5]
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: negative, isWarm: true), nil,
                "负值返回 nil")
    let oversized: [String: Any] = ["Device Utilization %": 150]
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: oversized, isWarm: true), nil,
                "超过 100 返回 nil")

    // 异常：字典本身为 nil
    assertEqual(SystemMetricsCalculations.gpuUtilization(statistics: nil, isWarm: true), nil,
                "nil 字典返回 nil")
}
