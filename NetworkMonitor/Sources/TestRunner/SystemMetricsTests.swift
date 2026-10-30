import Foundation
import NetworkMonitorCore

// MARK: - 系统监控采样口径

/// SystemMetrics 模型 / 展示口径 / 历史缓冲 / 偏好 — 正常 + 边界 + 异常
func runSystemMetricsTests() {
    print("\n🧪 Testing SystemMetrics...")
    do {
        testPercentText()
        testByteRateText()
        testCapacityRatio()
        testSplitCores()
        testMemoryPressureLevel()
        testHistory()
        testSnapshotEquality()
        testPreferences()
        runSystemMetricsCalculationTests()
    }
}

// MARK: - 百分比格式化

private func testPercentText() {
    assertEqual(SystemMetricsFormatting.percentText(0.5), "50%", "0.5 → 50%")
    assertEqual(SystemMetricsFormatting.percentText(1.0), "100%", "满格 1.0 → 100%")
    assertEqual(SystemMetricsFormatting.percentText(0), "0%", "0 → 0%")

    // 边界：越界比例封顶 / 兜底
    assertEqual(SystemMetricsFormatting.percentText(1.5), "100%", "超过 1 的比例封顶 100%")
    assertEqual(SystemMetricsFormatting.percentText(-0.2), "0%", "负比例按 0 处理")
    assertEqual(SystemMetricsFormatting.percentText(.nan), "0%", "NaN 兜底 0%")
    assertEqual(SystemMetricsFormatting.percentText(.infinity), "0%", "无穷兜底 0%")

    // 四舍五入
    assertEqual(SystemMetricsFormatting.percentText(0.005), "1%", "0.005 四舍五入到 1%")
    assertEqual(SystemMetricsFormatting.percentText(0.004), "0%", "0.004 四舍五入到 0%")
}

// MARK: - 字节速率格式化

private func testByteRateText() {
    assertEqual(SystemMetricsFormatting.byteRateText(nil), "—", "nil（不可得）显示占位符")
    assertEqual(SystemMetricsFormatting.byteRateText(0), "0 B/s", "0 字节")
    assertEqual(SystemMetricsFormatting.byteRateText(512), "512 B/s", "B 级取整")
    assertEqual(SystemMetricsFormatting.byteRateText(1_536), "1.5 KB/s", "KB 级保留 1 位")
    assertEqual(SystemMetricsFormatting.byteRateText(1_048_576), "1.0 MB/s", "MB 级保留 1 位")
    assertEqual(SystemMetricsFormatting.byteRateText(1_500_000), "1.4 MB/s", "非整倍数保留 1 位")
    assertEqual(SystemMetricsFormatting.byteRateText(2_147_483_648), "2.0 GB/s", "GB 级")

    // 边界 / 异常
    assertEqual(SystemMetricsFormatting.byteRateText(-1_536), "1.5 KB/s", "负速率按绝对值")
    assertEqual(SystemMetricsFormatting.byteRateText(.infinity), "—", "无穷视为不可得")
    assertEqual(SystemMetricsFormatting.byteRateText(.nan), "—", "NaN 视为不可得")
    assertEqual(SystemMetricsFormatting.byteRateText(1_099_511_627_776), "1.0 TB/s", "TB 级")
}

// MARK: - 容量占比

private func testCapacityRatio() {
    assertEqual(SystemMetricsFormatting.capacityRatio(used: 500, total: 1_000), 0.5, "500/1000 = 0.5")
    assertEqual(SystemMetricsFormatting.capacityRatio(used: 0, total: 1_000), 0, "空盘")
    assertEqual(SystemMetricsFormatting.capacityRatio(used: 1_000, total: 1_000), 1, "满盘")

    // 边界：除零与越界
    assertEqual(SystemMetricsFormatting.capacityRatio(used: 0, total: 0), 0, "总量 0 不产生除零")
    assertEqual(SystemMetricsFormatting.capacityRatio(used: 2_000, total: 1_000), 1, "已用超过总量封顶 1")
    assertEqual(SystemMetricsFormatting.capacityRatio(used: .max, total: .max), 1, "超大值不溢出")
}

// MARK: - 每核 P/E 分组

private func testSplitCores() {
    let cores: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    let grouped = SystemMetricsFormatting.splitCores(perCore: cores, performanceCores: 8, efficiencyCores: 2)
    assertEqual(grouped.performance.count, 8, "8P + 2E：P 核 8 个")
    assertEqual(grouped.efficiency, [0.1, 0.2], "E 核在前（实测逻辑 CPU 0、1 为 E 核）")
    assertEqual(grouped.performance.first, 0.3, "P 核取 E 核之后的 8 个")

    // 边界：0 核 / P、E 全 0 / 数量超出实际核数 / 负数
    let empty = SystemMetricsFormatting.splitCores(perCore: [], performanceCores: 8, efficiencyCores: 2)
    assertEqual(empty.performance.isEmpty, true, "0 核时 P 组为空")
    assertEqual(empty.efficiency.isEmpty, true, "0 核时 E 组为空")

    let noPerfInfo = SystemMetricsFormatting.splitCores(perCore: cores, performanceCores: 0, efficiencyCores: 0)
    assertEqual(noPerfInfo.performance.isEmpty, true, "P/E 数量为 0 时不猜分组")
    assertEqual(noPerfInfo.efficiency.isEmpty, true, "P/E 数量为 0 时 E 组为空")

    let oversized = SystemMetricsFormatting.splitCores(perCore: [0.1, 0.2, 0.3], performanceCores: 8, efficiencyCores: 8)
    assertEqual(oversized.efficiency.count, 3, "E 数量超出实际核数时按实际返回")
    assertEqual(oversized.performance.isEmpty, true, "E 核占满时 P 组为空")

    let negative = SystemMetricsFormatting.splitCores(perCore: [0.1], performanceCores: -1, efficiencyCores: -1)
    assertEqual(negative.performance.isEmpty, true, "负数按 0 处理")
    assertEqual(negative.efficiency.isEmpty, true, "负数按 0 处理")

    let exact = SystemMetricsFormatting.splitCores(perCore: [0.1, 0.2, 0.3, 0.4, 0.5],
                                                   performanceCores: 3, efficiencyCores: 2)
    assertEqual(exact.efficiency, [0.1, 0.2], "精确切分 E（前 2 个）")
    assertEqual(exact.performance, [0.3, 0.4, 0.5], "精确切分 P（后 3 个）")
}

// MARK: - 内存压力等级

private func testMemoryPressureLevel() {
    assertEqual(MemoryPressureLevel(sysctlRawValue: 1), .normal, "1 = 正常")
    assertEqual(MemoryPressureLevel(sysctlRawValue: 2), .warning, "2 = 警示")
    assertEqual(MemoryPressureLevel(sysctlRawValue: 4), .critical, "4 = 紧张")

    // 异常：未知原始值不能误判成正常
    assertEqual(MemoryPressureLevel(sysctlRawValue: 0), nil, "0 是未知值")
    assertEqual(MemoryPressureLevel(sysctlRawValue: 3), nil, "3 是未知值")
    assertEqual(MemoryPressureLevel(sysctlRawValue: 5), nil, "5 是未知值")
}

// MARK: - 环形历史缓冲

private func testHistory() {
    // 空历史
    var history = SystemMetricsHistory(capacity: 3)
    assertEqual(history.isEmpty, true, "新历史为空")
    assertEqual(history.maxCPUUsage, nil, "空历史没有 CPU 峰值")
    assertEqual(history.maxMemoryRatio, nil, "空历史没有内存峰值")

    // 正常：写满后按时间正序返回最后 3 帧
    for index in 1...3 {
        history.append(makeSnapshot(second: TimeInterval(index), cpuUsage: Double(index) / 10))
    }
    assertEqual(history.count, 3, "容量 3 写满")
    assertEqual(history.values.map { Int($0.timestamp.timeIntervalSince1970) }, [1, 2, 3],
                "未覆盖时按时间正序")

    // 边界：覆盖最旧一条
    history.append(makeSnapshot(second: 4, cpuUsage: 0.4))
    assertEqual(history.count, 3, "超出容量后条数不变")
    assertEqual(history.values.map { Int($0.timestamp.timeIntervalSince1970) }, [2, 3, 4],
                "写满后覆盖最旧一条")
    assertEqual(history.maxCPUUsage, 0.4, "峰值取所有帧的最大值")

    // 容量 1
    var single = SystemMetricsHistory(capacity: 1)
    single.append(makeSnapshot(second: 1, cpuUsage: 0.1))
    single.append(makeSnapshot(second: 2, cpuUsage: 0.9))
    assertEqual(single.values.count, 1, "容量 1 只保留最新一帧")
    assertEqual(single.values.first?.timestamp.timeIntervalSince1970, 2, "容量 1 保留最新")

    // 异常：total 为 0 的内存快照不参与峰值
    var zeroMemory = SystemMetricsHistory(capacity: 2)
    zeroMemory.append(SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: 1),
                                            memory: MemorySnapshot(used: 100, total: 0,
                                                                   pressure: .normal, swapUsed: 0,
                                                                   swapTotal: 0, compressed: 0)))
    assertEqual(zeroMemory.maxMemoryRatio, nil, "total 0 不产生 NaN 峰值")
}

// MARK: - 快照模型

private func testSnapshotEquality() {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    // 异常：全 nil 快照（所有采集失败）也必须能构造与比较
    let empty = SystemMetricsSnapshot(timestamp: timestamp)
    assertEqual(empty == SystemMetricsSnapshot(timestamp: timestamp), true, "全 nil 快照相等")
    assertEqual(empty.cpu == nil, true, "全 nil 快照 CPU 不可得")
    assertEqual(empty.memory == nil, true, "全 nil 快照内存不可得")

    // 正常：字段差异会导致不等
    let cpu = CPUSnapshot(totalUsage: 0.25, perCore: [0.2, 0.3],
                          performanceCores: 8, efficiencyCores: 2,
                          userUsage: 0.1, systemUsage: 0.05)
    let full = SystemMetricsSnapshot(timestamp: timestamp,
                                     cpu: cpu,
                                     gpu: GPUSnapshot(utilization: 0.5, memoryUsed: 1024),
                                     memory: MemorySnapshot(used: 4, total: 8, pressure: .warning,
                                                            swapUsed: 2, swapTotal: 4, compressed: 1),
                                     disk: DiskSnapshot(used: 100, total: 200,
                                                        readBytesPerSecond: 1024,
                                                        writeBytesPerSecond: nil),
                                     thermal: ThermalSnapshot(cpuTemperatureCelsius: 45))
    assertEqual(full.cpu?.totalUsage, 0.25, "CPU 利用率保留")
    assertEqual(full.disk?.writeBytesPerSecond, nil, "磁盘写入速率不可得时保持 nil")
    assertEqual(full.thermal?.isEmpty, false, "有温度时不为空")

    let changed = SystemMetricsSnapshot(timestamp: timestamp,
                                        cpu: CPUSnapshot(totalUsage: 0.5, perCore: [0.5, 0.5],
                                                         performanceCores: 8, efficiencyCores: 2))
    assertEqual(full == changed, false, "不同快照不相等")
    assertEqual(ThermalSnapshot().isEmpty, true, "空温度快照 isEmpty")
}

// MARK: - 偏好

private func testPreferences() {
    let storage = InMemoryStorage()
    let preferences = SystemMonitorPreferences(storage: storage)

    // 默认值
    assertEqual(preferences.isPanelItemVisible(.cpu), true, "CPU 默认显示")
    assertEqual(preferences.isPanelItemVisible(.gpu), true, "GPU 默认显示")
    assertEqual(preferences.isPanelItemVisible(.memory), true, "内存默认显示")
    assertEqual(preferences.isPanelItemVisible(.disk), true, "磁盘默认显示")
    assertEqual(preferences.isPanelItemVisible(.thermal), true, "温度默认显示")
    assertEqual(SystemMonitorPreferences.PanelItem.allCases.count, 5, "面板显示项共 5 项（CPU/GPU/内存/磁盘/温度）")
    let defaultVisible = SystemMonitorPreferences.PanelItem.allCases.filter { preferences.isPanelItemVisible($0) }
    assertEqual(defaultVisible.count, 5, "默认全部 5 项可见")
    assertEqual(preferences.showsCPUInMenuBar, false, "菜单栏默认不显示 CPU 百分比")
    assertEqual(preferences.sampleInterval, 1.0, "默认采样周期 1 秒")

    // 写入回读
    preferences.setPanelItemVisible(true, for: .thermal)
    assertEqual(preferences.isPanelItemVisible(.thermal), true, "温度开关可写入")
    preferences.setPanelItemVisible(false, for: .cpu)
    assertEqual(preferences.isPanelItemVisible(.cpu), false, "关闭 CPU 显示可写入")
    preferences.showsCPUInMenuBar = true
    assertEqual(preferences.showsCPUInMenuBar, true, "菜单栏开关可写入")

    // 边界：采样周期收敛到 [0.5, 5.0]
    preferences.sampleInterval = 0.1
    assertEqual(preferences.sampleInterval, 0.5, "过小周期收敛到 0.5")
    preferences.sampleInterval = 30
    assertEqual(preferences.sampleInterval, 5.0, "过大周期收敛到 5.0")

    // 异常：非法值回退默认
    storage.set(0.0, forKey: "systemMonitor.sampleInterval")
    assertEqual(preferences.sampleInterval, 1.0, "0 周期回退默认")
    storage.set(Double.nan, forKey: "systemMonitor.sampleInterval")
    assertEqual(preferences.sampleInterval, 1.0, "NaN 周期回退默认")
}

// MARK: - 构造辅助

private func makeSnapshot(second: TimeInterval, cpuUsage: Double) -> SystemMetricsSnapshot {
    SystemMetricsSnapshot(timestamp: Date(timeIntervalSince1970: second),
                          cpu: CPUSnapshot(totalUsage: cpuUsage, perCore: [cpuUsage],
                                           performanceCores: 1, efficiencyCores: 0),
                          memory: MemorySnapshot(used: 1, total: 4, pressure: .normal,
                                                 swapUsed: 0, swapTotal: 0, compressed: 0))
}
