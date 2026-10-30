import Foundation
import NetworkMonitorCore

// MARK: - 第二批 P0 指标断言（续）：Top-N / 功耗 / 电池
//
// 拆出原因：与 SystemMetricsSupplementTests.swift 合计超过单文件 15360 字节门禁，
// 按主题拆分；由 runSystemMetricsSupplementTests() 末尾调用，main.swift 不变。

/// 进程 Top-N 排序截断 / GPU 功耗换算 / 负载与电池模型
func runSystemMetricsProcessAndPowerTests() {
    testProcessTopN()
    testGPUPowerConversion()
    testLoadSnapshotModel()
    testBatterySnapshotModel()
}

// MARK: - 进程 Top-N 排序与截断

private func makeBaselines(_ rows: [(Int32, UInt64, UInt64)]) -> [Int32: ProcessCPUTimeBaseline] {
    var result = [Int32: ProcessCPUTimeBaseline]()
    for (pid, ticks, resident) in rows {
        result[pid] = ProcessCPUTimeBaseline(cpuTicks: ticks, residentBytes: resident)
    }
    return result
}

private func testProcessTopN() {
    let nsPerTick = 41.666666666666664
    // pid 1：CPU 高内存低；pid 2：CPU 低内存高；pid 3/4/5 中等
    let previous = makeBaselines([
        (1, 0, 1_000_000), (2, 0, 9_000_000), (3, 0, 3_000_000),
        (4, 0, 2_000_000), (5, 0, 500_000),
    ])
    let fullCore = UInt64(1_000_000_000 / nsPerTick)
    let current = makeBaselines([
        (1, fullCore, 1_000_000),          // 100%
        (2, fullCore / 10, 9_000_000),     // 10%
        (3, fullCore / 2, 3_000_000),      // 50%
        (4, fullCore / 4, 2_000_000),      // 25%
        (5, 0, 500_000),                   // 0%
    ])
    let names: [Int32: String] = [1: "alpha", 2: "beta", 3: "gamma", 4: "delta", 5: "epsilon"]

    let top = SystemMetricsSupplementCalculations.processTopN(previous: previous,
                                                              current: current,
                                                              names: names,
                                                              nanosecondsPerTick: nsPerTick,
                                                              elapsedSeconds: 1,
                                                              limit: 3)
    guard let top else {
        assertNotNil(nil as [ProcessResourceUsage]?, "Top-N 应返回结果")
        return
    }
    assertEqual(top.scanned, 5, "scanned 为本次读到的进程数")
    // CPU 榜按降序截断到 3
    assertEqual(top.cpu.map { $0.pid }, [1, 3, 4], "CPU 榜按 cpuPercent 降序取前 3")
    assertEqual((top.cpu.first?.cpuPercent).map { abs($0 - 100) < 0.001 }, true, "榜首 CPU% ≈ 100")
    assertEqual(top.cpu.first?.name, "alpha", "进程名按 pid 映射")
    // 内存榜独立排序
    assertEqual(top.memory.map { $0.pid }, [2, 3, 4], "内存榜按 residentBytes 降序取前 3")

    // 边界：首帧（无基线）→ nil，不把「还没测」显示成 0
    assertEqual(SystemMetricsSupplementCalculations.processTopN(previous: nil,
                                                                current: current,
                                                                names: names,
                                                                nanosecondsPerTick: nsPerTick,
                                                                elapsedSeconds: 1,
                                                                limit: 5) == nil, true,
                "首帧返回 nil")

    // 边界：current 为空 → nil
    assertEqual(SystemMetricsSupplementCalculations.processTopN(previous: previous,
                                                                current: [:],
                                                                names: [:],
                                                                nanosecondsPerTick: nsPerTick,
                                                                elapsedSeconds: 1,
                                                                limit: 5) == nil, true,
                "本次为空返回 nil")

    // 边界：一个 pid 都配不上（进程全换）→ nil，与首帧同口径
    let strangers = makeBaselines([(99, fullCore, 1_000)])
    assertEqual(SystemMetricsSupplementCalculations.processTopN(previous: previous,
                                                                current: strangers,
                                                                names: [99: "new"],
                                                                nanosecondsPerTick: nsPerTick,
                                                                elapsedSeconds: 1,
                                                                limit: 5) == nil, true,
                "无任何配对 pid 返回 nil")

    // 边界：新插入 pid 不参与（没有基线算不出差）
    var withNewcomer = current
    withNewcomer[7] = ProcessCPUTimeBaseline(cpuTicks: fullCore * 10, residentBytes: 99_000_000)
    let filtered = SystemMetricsSupplementCalculations.processTopN(previous: previous,
                                                                   current: withNewcomer,
                                                                   names: names,
                                                                   nanosecondsPerTick: nsPerTick,
                                                                   elapsedSeconds: 1,
                                                                   limit: 5)
    assertEqual(filtered?.scanned, 6, "scanned 含新进程")
    assertEqual(filtered?.memory.first?.pid, 2, "新进程无基线不进榜（内存榜仍是原榜首）")

    // 边界：limit ≤ 0 → 空榜单
    let zeroLimit = SystemMetricsSupplementCalculations.processTopN(previous: previous,
                                                                   current: current,
                                                                   names: names,
                                                                   nanosecondsPerTick: nsPerTick,
                                                                   elapsedSeconds: 1,
                                                                   limit: 0)
    assertEqual(zeroLimit?.cpu.isEmpty, true, "limit 0 → CPU 榜为空")
    assertEqual(zeroLimit?.memory.isEmpty, true, "limit 0 → 内存榜为空")

    // 边界：limit 超过进程数 → 全给
    let oversized = SystemMetricsSupplementCalculations.processTopN(previous: previous,
                                                                   current: current,
                                                                   names: names,
                                                                   nanosecondsPerTick: nsPerTick,
                                                                   elapsedSeconds: 1,
                                                                   limit: 100)
    assertEqual(oversized?.cpu.count, 5, "limit 超量时按实际进程数返回")

    // 异常：计数倒退的进程跳过，不产生负百分比也不进榜
    let backwards = makeBaselines([(1, 100, 1_000_000), (2, fullCore, 9_000_000)])
    let somePrevious = makeBaselines([(1, 5000, 1_000_000), (2, 0, 9_000_000)])
    let skipped = SystemMetricsSupplementCalculations.processTopN(previous: somePrevious,
                                                                 current: backwards,
                                                                 names: [1: "a", 2: "b"],
                                                                 nanosecondsPerTick: nsPerTick,
                                                                 elapsedSeconds: 1,
                                                                 limit: 5)
    assertEqual(skipped?.cpu.map { $0.pid }, [2], "倒退进程被跳过，只留正常进程")
}

// MARK: - GPU 功耗换算

private func testGPUPowerConversion() {
    // 正常：1 秒消耗 290,295,980 nJ = 0.2903 W（实测空闲值）
    assertEqual(SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: 290_295_980,
                                                                        elapsedSeconds: 1),
                0.29029598, "290295980 nJ / 1s = 0.2903 W")
    // 正常：2 秒窗口同能量 → 半瓦
    assertEqual(SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: 290_295_980,
                                                                        elapsedSeconds: 2),
                0.14514799, "同一能量摊到 2 秒 = 0.1451 W")
    // 正常：Metal 压满实测 2.56 W
    let load = SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: 2_560_500_280,
                                                                        elapsedSeconds: 1)
    assertEqual(load.map { abs($0 - 2.56050028) < 0.001 }, true, "压满 2560500280 nJ = 2.56 W")

    // 边界：时间差 ≤ 0 返回 nil
    assertEqual(SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: 1000,
                                                                        elapsedSeconds: 0), nil,
                "时间差 0 返回 nil")
    assertEqual(SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: 1000,
                                                                        elapsedSeconds: -1), nil,
                "负时间差返回 nil")

    // 边界：越界（> 1000 W）判为通道异常
    assertEqual(SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: UInt64.max,
                                                                        elapsedSeconds: 0.001), nil,
                "超大能量按通道异常返回 nil")
    // 边界：0 能量是有效读数
    assertEqual(SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: 0, elapsedSeconds: 1), 0,
                "0 能量 → 0 W")

    // 累计能量差：倒退按 0
    assertEqual(SystemMetricsSupplementCalculations.energyDelta(previous: 100, current: 400), 300,
                "正向能量差")
    assertEqual(SystemMetricsSupplementCalculations.energyDelta(previous: 400, current: 100), 0,
                "倒退归零，不出负值")
}

// MARK: - 负载模型

private func testLoadSnapshotModel() {
    let snapshot = LoadSnapshot(load1: 2.5, load5: 3.0, load15: 4.0, coreCount: 10,
                                thermalState: .fair, isLowPowerModeEnabled: true)
    assertEqual(snapshot.load1, 2.5, "load1 保留")
    assertEqual(snapshot.coreCount, 10, "核数保留")
    assertEqual(snapshot.thermalState, .fair, "热压力等级保留")
    assertEqual(snapshot.isLowPowerModeEnabled, true, "低电量模式保留")

    // 边界：默认值（旧调用点零改动）
    let minimal = LoadSnapshot(load1: 0, load5: 0, load15: 0, coreCount: 0)
    assertEqual(minimal.thermalState, .unknown, "缺省热压力为 unknown（不猜成 nominal）")
    assertEqual(minimal.isLowPowerModeEnabled, false, "缺省低电量模式为 false")

    // 异常：未知档位不误判
    assertEqual(ThermalStateLevel(rawValue: "nonexistent"), nil, "未知档位返回 nil")
}

// MARK: - 电池模型

private func testBatterySnapshotModel() {
    let snapshot = BatterySnapshot(percentage: 0.8, isCharging: false, isOnAC: true,
                                   cycleCount: 89, adapterWatts: 94)
    assertEqual(snapshot.percentage, 0.8, "电量比例 80%")
    assertEqual(snapshot.isOnAC, true, "AC 供电")
    assertEqual(snapshot.cycleCount, 89, "循环次数保留")
    assertEqual(snapshot.adapterWatts, 94, "适配器 94 W")
    assertEqual(snapshot.isEmpty, false, "有值不为空")

    // 边界：台式机无电池 → 全 nil，isEmpty 为 true
    assertEqual(BatterySnapshot().isEmpty, true, "全 nil 电池快照 isEmpty")
    // 边界：只有循环次数也算有值（不能整体丢弃）
    assertEqual(BatterySnapshot(cycleCount: 0).isEmpty, false, "0 次循环是有效读数")

    // 边界：快照字段默认值不破坏旧调用点
    let legacy = SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: 1))
    assertEqual(legacy.load, nil, "旧调用点 load 缺省为 nil")
    assertEqual(legacy.processes, nil, "旧调用点 processes 缺省为 nil")
    assertEqual(legacy.battery, nil, "旧调用点 battery 缺省为 nil")

    // 边界：新增字段参与 Equatable（UI 靠比较判重）
    let a = SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: 1),
                                  load: LoadSnapshot(load1: 1, load5: 1, load15: 1, coreCount: 8))
    let b = SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: 1),
                                  load: LoadSnapshot(load1: 2, load5: 1, load15: 1, coreCount: 8))
    assertEqual(a == b, false, "load 不同即快照不等")
}