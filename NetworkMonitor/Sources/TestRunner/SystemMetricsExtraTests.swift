import Foundation
import NetworkMonitorCore

// MARK: - 系统监控扩展口径断言（内存拆分 / 磁盘 IOPS / CPU user-system）
//
// 拆出原因：SystemMetricsTests.swift 已接近单文件 15360 字节上限，
// 新增断言另开本文件；注册入口仍由 runSystemMetricsTests() 末尾调用，
// main.swift 的调度顺序不变。

/// 内存 wired / active / inactive 拆分 + 磁盘 IOPS / 繁忙度 + CPU user/system 口径
func runSystemMetricsExtraTests() {
    testMemorySplitFields()
    testDiskIOCounterDeltas()
    testDiskBusyFraction()
    testDiskThroughput()
    testCPUUserSystemSemantics()
}

// MARK: - 内存拆分字段

private func testMemorySplitFields() {
    // 正常：三个拆分字段各自保留，used 口径仍是 active + wired + compressed
    let snapshot = MemorySnapshot(used: 900,
                                  total: 1_600,
                                  pressure: .normal,
                                  swapUsed: 0,
                                  swapTotal: 0,
                                  compressed: 100,
                                  active: 500,
                                  wired: 300,
                                  inactive: 200)
    assertEqual(snapshot.active, 500, "active 原样保留")
    assertEqual(snapshot.wired, 300, "wired 原样保留")
    assertEqual(snapshot.inactive, 200, "inactive 原样保留")
    assertEqual(snapshot.active + snapshot.wired + snapshot.compressed, snapshot.used,
                "used = active + wired + compressed（不含 inactive）")
    assertEqual(snapshot.inactive > 0, true, "inactive 单独成字段，不并入 used")

    // 边界：旧调用点不传拆分字段 → 默认 0，构造与相等比较照常成立
    let legacy = MemorySnapshot(used: 4, total: 8, pressure: .warning,
                                swapUsed: 2, swapTotal: 4, compressed: 1)
    assertEqual(legacy.active, 0, "缺省 active 为 0")
    assertEqual(legacy.wired, 0, "缺省 wired 为 0")
    assertEqual(legacy.inactive, 0, "缺省 inactive 为 0")
    assertEqual(legacy, MemorySnapshot(used: 4, total: 8, pressure: .warning,
                                       swapUsed: 2, swapTotal: 4, compressed: 1),
                "缺省拆分字段不破坏相等比较")

    // 边界：拆分字段不同 → 快照不等（参与 Equatable，UI 才能靠比较判重）
    let changed = MemorySnapshot(used: 4, total: 8, pressure: .warning,
                                 swapUsed: 2, swapTotal: 4, compressed: 1,
                                 active: 1, wired: 1, inactive: 1)
    assertEqual(legacy == changed, false, "拆分字段不同即不相等")
}

// MARK: - 磁盘累计计数器差分

private func testDiskIOCounterDeltas() {
    // 正常：1 秒内 +2048 字节 / +20 次操作
    assertEqual(SystemMetricsCalculations.operationsPerSecond(previous: 1_000, current: 1_020, elapsed: 1),
                20, "1 秒 +20 次 → 20 IOPS")
    assertEqual(SystemMetricsCalculations.operationsPerSecond(previous: 1_000, current: 1_000, elapsed: 2),
                0, "操作数不变 → 0 IOPS")

    // 边界：时间差 ≤ 0 不除零
    assertEqual(SystemMetricsCalculations.operationsPerSecond(previous: 0, current: 100, elapsed: 0), nil,
                "时间差 0 返回 nil")
    assertEqual(SystemMetricsCalculations.operationsPerSecond(previous: 0, current: 100, elapsed: -1), nil,
                "负时间差返回 nil")

    // 边界：计数器倒退（重置 / 换设备）→ nil，不返回负 IOPS
    assertEqual(SystemMetricsCalculations.operationsPerSecond(previous: 500, current: 100, elapsed: 1), nil,
                "计数器倒退返回 nil")

    // 正常 + 边界：counterDelta 对倒退按 0 处理
    assertEqual(SystemMetricsCalculations.counterDelta(previous: 100, current: 250), 150, "正向增量")
    assertEqual(SystemMetricsCalculations.counterDelta(previous: 100, current: 100), 0, "零增量")
    assertEqual(SystemMetricsCalculations.counterDelta(previous: 250, current: 100), 0, "倒退归零，不出负值")
}

// MARK: - 磁盘繁忙度

private func testDiskBusyFraction() {
    // 正常：(0.3s + 0.2s) / 1s = 0.5
    assertEqual(SystemMetricsCalculations.busyFraction(readNanoseconds: 300_000_000,
                                                       writeNanoseconds: 200_000_000,
                                                       elapsed: 1),
                0.5, "读 0.3s + 写 0.2s / 1s = 50%")

    // 正常：纳秒换算是除以 1e9（不是 1e6）
    assertEqual(SystemMetricsCalculations.busyFraction(readNanoseconds: 1_000_000_000,
                                                       writeNanoseconds: 0,
                                                       elapsed: 2),
                0.5, "1e9 纳秒 = 1 秒，除以 2 秒 = 0.5")

    // 边界：闲置 → 0
    assertEqual(SystemMetricsCalculations.busyFraction(readNanoseconds: 0, writeNanoseconds: 0, elapsed: 1),
                0, "完全闲置为 0")

    // 边界：多盘并行时服务时间之和可超过采样间隔 → 封顶 1，不出现 150%
    assertEqual(SystemMetricsCalculations.busyFraction(readNanoseconds: 1_000_000_000,
                                                       writeNanoseconds: 500_000_000,
                                                       elapsed: 1),
                1, "超过采样间隔封顶 1")

    // 边界：时间差 ≤ 0 不除零
    assertEqual(SystemMetricsCalculations.busyFraction(readNanoseconds: 1, writeNanoseconds: 1, elapsed: 0),
                nil, "时间差 0 返回 nil")
    assertEqual(SystemMetricsCalculations.busyFraction(readNanoseconds: 1, writeNanoseconds: 1, elapsed: -1),
                nil, "负时间差返回 nil")
}

// MARK: - 磁盘整机聚合

private func testDiskThroughput() {
    // 正常：两块盘按 entryID 配对，速率 / IOPS / 繁忙度分别累加
    let previous: [UInt64: DiskIOCounters] = [
        1: DiskIOCounters(readBytes: 1_000, writeBytes: 2_000,
                          readOperations: 10, writeOperations: 20,
                          readTotalTime: 0, writeTotalTime: 0),
        2: DiskIOCounters(readBytes: 5_000, writeBytes: 6_000,
                          readOperations: 50, writeOperations: 60,
                          readTotalTime: 0, writeTotalTime: 0),
    ]
    let current: [UInt64: DiskIOCounters] = [
        1: DiskIOCounters(readBytes: 2_000, writeBytes: 4_000,
                          readOperations: 20, writeOperations: 40,
                          readTotalTime: 100_000_000, writeTotalTime: 100_000_000),
        2: DiskIOCounters(readBytes: 7_000, writeBytes: 8_000,
                          readOperations: 70, writeOperations: 80,
                          readTotalTime: 0, writeTotalTime: 0),
    ]
    guard let throughput = SystemMetricsCalculations.diskThroughput(previous: previous,
                                                                   current: current,
                                                                   elapsed: 1) else {
        assertNotNil(nil as DiskThroughput?, "两盘配对应返回吞吐")
        return
    }
    assertEqual(throughput.readBytesPerSecond, 3_000, "读速率 = 1000 + 2000")
    assertEqual(throughput.writeBytesPerSecond, 4_000, "写速率 = 2000 + 2000")
    assertEqual(throughput.readIOPS, 30, "读 IOPS = 10 + 20")
    assertEqual(throughput.writeIOPS, 40, "写 IOPS = 20 + 20")
    assertEqual(throughput.busyFraction, 0.2, "繁忙度 = 0.2s / 1s")

    // 边界：首帧（无基线）→ nil，不返回全 0
    assertEqual(SystemMetricsCalculations.diskThroughput(previous: nil, current: current, elapsed: 1), nil,
                "无基线返回 nil（首帧口径）")

    // 边界：当前表为空
    assertEqual(SystemMetricsCalculations.diskThroughput(previous: previous, current: [:], elapsed: 1), nil,
                "当前表为空返回 nil")

    // 边界：一个 entryID 都配不上（换盘）→ nil
    let replaced: [UInt64: DiskIOCounters] = [
        9: DiskIOCounters(readBytes: 10, writeBytes: 10, readOperations: 1, writeOperations: 1),
    ]
    assertEqual(SystemMetricsCalculations.diskThroughput(previous: previous, current: replaced, elapsed: 1), nil,
                "entryID 完全不匹配返回 nil")

    // 边界：新插入的 entryID 不参与累计（拔插不产生虚高速率）
    let withNewcomer = current.merging([7: DiskIOCounters(readBytes: 999_999, writeBytes: 999_999,
                                                          readOperations: 999, writeOperations: 999)]) { _, new in new }
    let partial = SystemMetricsCalculations.diskThroughput(previous: previous,
                                                           current: withNewcomer,
                                                           elapsed: 1)
    assertEqual(partial?.readIOPS, 30, "新插入 entryID 不计入（读数仍为两盘之差）")

    // 边界：单盘计数器倒退按 0 增量处理，不产生负值
    let backwards: [UInt64: DiskIOCounters] = [
        1: DiskIOCounters(readBytes: 500, writeBytes: 500,
                          readOperations: 5, writeOperations: 5,
                          readTotalTime: 0, writeTotalTime: 0),
    ]
    let reset = SystemMetricsCalculations.diskThroughput(previous: previous, current: backwards, elapsed: 1)
    assertEqual(reset?.readBytesPerSecond, 0, "计数器倒退按 0 增量处理")
    assertEqual(reset?.busyFraction, 0, "倒退不产生负繁忙度")

    // 边界：时间差 ≤ 0 → nil
    assertEqual(SystemMetricsCalculations.diskThroughput(previous: previous, current: current, elapsed: 0), nil,
                "时间差 0 返回 nil")
}

// MARK: - CPU user / system 口径

private func testCPUUserSystemSemantics() {
    // 口径：user / system 占「全部 ticks」（含 idle），不是占忙时
    let previous: [UInt32] = [0, 0, 0, 0]
    let current: [UInt32] = [30, 20, 50, 0]
    guard let sample = SystemMetricsCalculations.cpuUsage(previous: previous, current: current) else {
        assertNotNil(nil as CPUUsageSample?, "CPU 差分应返回结果")
        return
    }
    assertEqual(sample.userUsage, 0.3, "user = 30/100（分母含 idle）")
    assertEqual(sample.systemUsage, 0.2, "system = 20/100（分母含 idle）")
    assertEqual(sample.totalUsage, 0.5, "总忙 = (30+20)/100")
    assertEqual(sample.userUsage + sample.systemUsage, sample.totalUsage,
                "user + system = 总忙（nice 为 0 时）")

    // 边界：nice 计入忙时，但不计入 user / system
    let niceSample = SystemMetricsCalculations.cpuUsage(previous: [0, 0, 0, 0],
                                                        current: [30, 20, 50, 10])
    assertEqual(niceSample?.totalUsage, 60.0 / 110.0, "nice 计入总忙：60/110")
    assertEqual(niceSample?.userUsage, 30.0 / 110.0, "nice 不计入 user")
    assertEqual(niceSample?.systemUsage, 20.0 / 110.0, "nice 不计入 system")

    // 异常：全部 idle → user / system 均为 0，不产生 NaN
    let idle = SystemMetricsCalculations.cpuUsage(previous: [0, 0, 0, 0], current: [0, 0, 100, 0])
    assertEqual(idle?.userUsage, 0, "全闲时 user 为 0")
    assertEqual(idle?.systemUsage, 0, "全闲时 system 为 0")

    // 异常：零 delta → 全 0，不产生 NaN / Inf
    let zero = SystemMetricsCalculations.cpuUsage(previous: current, current: current)
    assertEqual(zero?.userUsage, 0, "零 delta：user 为 0")
    assertEqual(zero?.systemUsage, 0, "零 delta：system 为 0")

    // 快照封装：user / system 可选，缺省为 nil（旧调用点零改动）
    let snapshot = CPUSnapshot(totalUsage: 0.5, perCore: [0.5],
                               performanceCores: 8, efficiencyCores: 2)
    assertEqual(snapshot.userUsage, nil, "未传 userUsage 时为 nil")
    assertEqual(snapshot.systemUsage, nil, "未传 systemUsage 时为 nil")
}
