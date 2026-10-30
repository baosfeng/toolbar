import Foundation
import NetworkMonitorCore

// MARK: - 二级详情页格式化（正常 / 边界）

/// 详情页纯函数断言 — 每核均值、分段占比、容量、热力档位、采样周期
func runSystemDetailFormattingTests() {
    print("\n🧪 Testing SystemDetailFormatting...")
    testPercentNumberText()
    testCompactPercentText()
    testMeanPercentText()
    testByteCountText()
    testCapacityTexts()
    testSharePercentText()
    testGPUStateText()
    testHeatTier()
    testHeatPercentText()
    testHeatGridLayout()
    testByteCountParts()
    testSampleIntervalText()
}

// MARK: - 百分比数值

private func testPercentNumberText() {
    assertEqual(SystemDetailFormatting.percentNumberText(0.22), "22", "0.22 → 22")
    assertEqual(SystemDetailFormatting.percentNumberText(1.0), "100", "满格 → 100")
    assertEqual(SystemDetailFormatting.percentNumberText(0), "0", "0 → 0")

    // 边界 / 异常
    assertEqual(SystemDetailFormatting.percentNumberText(0.005), "1", "四舍五入到整数")
    assertEqual(SystemDetailFormatting.percentNumberText(1.5), "100", "越界封顶")
    assertEqual(SystemDetailFormatting.percentNumberText(-0.2), "0", "负比例归 0")
    assertEqual(SystemDetailFormatting.percentNumberText(.nan), "0", "NaN 归 0")
    assertEqual(SystemDetailFormatting.percentNumberText(.greatestFiniteMagnitude), "100",
                "超大数值封顶 100（不溢出成负 / 科学计数）")
}

// MARK: - 紧凑百分比

private func testCompactPercentText() {
    assertEqual(SystemDetailFormatting.compactPercentText(0.012875), "1.3%", "P 核均 1.2875%")
    assertEqual(SystemDetailFormatting.compactPercentText(0.40), "40%", "整数百分比不带小数位")
    assertEqual(SystemDetailFormatting.compactPercentText(0), "0%", "0 → 0%")
    assertEqual(SystemDetailFormatting.compactPercentText(0.644), "64.4%", "内存已用 64.4%")
    assertEqual(SystemDetailFormatting.compactPercentText(1.5), "100%", "越界封顶")
    assertEqual(SystemDetailFormatting.compactPercentText(.nan), "0%", "NaN 归 0")
}

// MARK: - 每核均值

private func testMeanPercentText() {
    let performance: [Double] = [0.012, 0.009, 0.024, 0.018, 0.007, 0.011, 0.009, 0.013]
    assertEqual(SystemDetailFormatting.meanCompactPercentText(performance), "1.3%",
                "P 核 8 个均值 1.2875%")
    assertEqual(SystemDetailFormatting.meanCompactPercentText([0.38, 0.42]), "40%",
                "E 核 2 个均值 40%")

    // 边界 / 异常
    assertEqual(SystemDetailFormatting.meanCompactPercentText([]), "—", "空数组显示「—」")
    assertEqual(SystemDetailFormatting.meanCompactPercentText([.nan, 0.5]), "50%",
                "NaN 不参与平均")
    assertEqual(SystemDetailFormatting.meanCompactPercentText([-1, -2]), "—",
                "全部非法值显示「—」")
    assertEqual(SystemDetailFormatting.meanCompactPercentText([2, 0]), "50%",
                "超过 1 的比例按 100% 参与平均")
}

// MARK: - 容量

private func testByteCountText() {
    assertEqual(SystemDetailFormatting.byteCountText(nil as UInt64?), "—", "nil 显示「—」")
    assertEqual(SystemDetailFormatting.byteCountText(UInt64(0)), "0 B", "0 字节")
    assertEqual(SystemDetailFormatting.byteCountText(UInt64(512)), "512 B", "B 级取整")
    assertEqual(SystemDetailFormatting.byteCountText(UInt64(1_536)), "1.5 KB", "KB 级 1 位小数")
    assertEqual(SystemDetailFormatting.byteCountText(UInt64(1_048_576)), "1.0 MB", "MB 级")
    assertEqual(SystemDetailFormatting.byteCountText(UInt64(16_106_127_360)), "15.0 GB",
                "15 GiB（1024 进位）→ 15.0 GB")

    // Double 入口（GPU 显存）
    assertEqual(SystemDetailFormatting.byteCountText(Double(557_700_000)), "531.9 MB",
                "GPU 显存 557.7 MB（按 1024 进位）")
    assertEqual(SystemDetailFormatting.byteCountText(nil as Double?), "—", "nil Double 显示「—」")
    assertEqual(SystemDetailFormatting.byteCountText(Double.nan), "—", "NaN 显示「—」")
    assertEqual(SystemDetailFormatting.byteCountText(Double(-5)), "0 B", "负数归 0")
    assertEqual(SystemDetailFormatting.byteCountText(UInt64.max), "16384.0 PB",
                "超大容量停在 PB 档，不越界成无单位数字")
}

private func testCapacityTexts() {
    assertEqual(SystemDetailFormatting.gigabyteValueText(11_059_540_787), "10.3",
                "10.3 GiB 的无单位数值")
    assertEqual(SystemDetailFormatting.gigabyteValueText(0), "0.0", "0 字节 → 0.0")
    assertEqual(SystemDetailFormatting.capacityPairText(used: 464_822_835_610,
                                                        total: 994_714_425_754),
                "432.9 GB / 926.4 GB", "磁盘容量行与原型同口径")
    assertEqual(SystemDetailFormatting.availableBytes(used: 100, total: 200), 100,
                "可用 = 总量 − 已用")
    assertEqual(SystemDetailFormatting.availableBytes(used: 300, total: 200), 0,
                "已用超总量时可用为 0（不出现负容量）")
}

// MARK: - 分段占比

private func testSharePercentText() {
    assertEqual(SystemDetailFormatting.sharePercentText(part: 100, total: 900), "11%",
                "100 / 900 → 11%")
    assertEqual(SystemDetailFormatting.sharePercentText(part: 0, total: 900), "0%",
                "0 → 0%")
    assertEqual(SystemDetailFormatting.sharePercentText(part: 900, total: 900), "100%",
                "满量 → 100%")

    // 边界 / 异常
    assertEqual(SystemDetailFormatting.sharePercentText(part: 100, total: 0), "—",
                "总量 0 显示「—」（与真的 0% 区分）")
    assertEqual(SystemDetailFormatting.sharePercentText(part: 1_200, total: 900), "100%",
                "部分超过总量封顶 100%")
    assertEqual(SystemDetailFormatting.sharePercentText(part: UInt64.max, total: 1), "100%",
                "超大分子不溢出")
}

// MARK: - GPU 状态 / 热力档位 / 采样周期

private func testGPUStateText() {
    assertEqual(SystemDetailFormatting.gpuStateText(utilization: 0), "空闲", "0% → 空闲")
    assertEqual(SystemDetailFormatting.gpuStateText(utilization: 0.08), "使用中", "> 0 → 使用中")
    assertEqual(SystemDetailFormatting.gpuStateText(utilization: .nan), "—", "NaN 显示「—」")
}

private func testHeatTier() {
    assertEqual(SystemDetailFormatting.heatTier(0.02), 0, "2% 常规档")
    assertEqual(SystemDetailFormatting.heatTier(0.09), 0, "9% 仍是常规档")
    assertEqual(SystemDetailFormatting.heatTier(0.10), 1, "10% 进中档")
    assertEqual(SystemDetailFormatting.heatTier(0.29), 1, "29% 仍是中档")
    assertEqual(SystemDetailFormatting.heatTier(0.30), 2, "30% 进高热档")
    assertEqual(SystemDetailFormatting.heatTier(1.5), 2, "越界按满格")
    assertEqual(SystemDetailFormatting.heatTier(.nan), 0, "NaN 按常规档")
    assertEqual(SystemDetailFormatting.heatTier(.greatestFiniteMagnitude), 2, "超大数值按满格")
}

private func testHeatPercentText() {
    assertEqual(SystemDetailFormatting.heatPercentText(0.012), "1.2", "1.2% 保留一位小数")
    assertEqual(SystemDetailFormatting.heatPercentText(0.38), "38", "38% 取整")
    assertEqual(SystemDetailFormatting.heatPercentText(0.004), "0.4", "0.4% 保留一位小数")
    assertEqual(SystemDetailFormatting.heatPercentText(0), "0", "0% 不带小数位")
    assertEqual(SystemDetailFormatting.heatPercentText(0.0996), "10", "9.96% 进位到 10")
    assertEqual(SystemDetailFormatting.heatPercentText(.nan), "0", "NaN 按 0")
}

/// 每核热力格布局 — 10 核必须 2 行 10 格（第 10 格 E1 不能被裁）
private func testHeatGridLayout() {
    assertEqual(SystemDetailFormatting.heatColumns, 9, "每行 9 格（与定稿原型一致）")

    // 行数 = ceil(n / 9)：整除去余数会漏掉最后一行
    assertEqual(SystemDetailFormatting.heatRowCount(10), 2, "10 核 → 2 行")
    assertEqual(SystemDetailFormatting.heatRowCount(9), 1, "9 核 → 1 行")
    assertEqual(SystemDetailFormatting.heatRowCount(1), 1, "1 核 → 1 行")
    assertEqual(SystemDetailFormatting.heatRowCount(0), 1, "空态也占 1 行（卡片不塌）")
    assertEqual(SystemDetailFormatting.heatRowCount(12), 2, "12 核 → 2 行")
    assertEqual(SystemDetailFormatting.heatRowCount(19), 3, "19 核 → 3 行")

    // 第 10 个核（index 9）落在第二行首列
    let last = SystemDetailFormatting.heatCellSlot(index: 9)
    assertEqual(last.row, 1, "第 10 格在第二行")
    assertEqual(last.column, 0, "第 10 格在第二行首列")
    assertEqual(SystemDetailFormatting.heatCellSlot(index: 8).column, 8, "第 9 格在第一行末列")

    // 可见格数 == 核数；全部格位落在网格高度内；槽位不重复
    let cellSize = 26.0
    let gap = 3.0
    let frames = SystemDetailFormatting.heatCellFrames(coreCount: 10,
                                                       cellSize: cellSize, gap: gap)
    assertEqual(frames.count, 10, "10 核 → 10 个格位（可见格数 == 核数）")
    let height = SystemDetailFormatting.heatContentHeight(coreCount: 10,
                                                          cellSize: cellSize, gap: gap)
    assertEqual(height, 55, "2 行 = 26 × 2 + 3 = 55pt")
    assertEqual(frames.allSatisfy { $0.minY + $0.height <= height }, true,
                "所有格位都在 2 行高度内（无越界裁切）")
    assertEqual(frames.last?.minY, 29, "第 10 格 y = 单行 26 + 间距 3")
    assertEqual(frames.last?.minX, 0, "第 10 格 x = 0（第二行首列）")
    let slots = (0..<frames.count).map { SystemDetailFormatting.heatCellSlot(index: $0) }
    assertEqual(Set(slots.map { "\($0.row)-\($0.column)" }).count, 10, "10 个格位互不重叠")
    assertEqual(frames.last.map { $0.minY + $0.height }, height,
                "最后一格底边正好等于网格高度（第 2 行被完整容纳）")

    // 扫一组核数：格数恒等于核数、行数恒等于 ceil(n / 9)
    for coreCount in [0, 1, 2, 8, 9, 10, 11, 17, 18, 19, 27] {
        let frames = SystemDetailFormatting.heatCellFrames(coreCount: coreCount,
                                                           cellSize: cellSize, gap: gap)
        let rows = SystemDetailFormatting.heatRowCount(coreCount)
        let expectedRows = max(1, (coreCount + 8) / 9)
        assertEqual(rows, expectedRows, "\(coreCount) 核行数 = ceil(n/9)")
        assertEqual(frames.count, coreCount, "\(coreCount) 核 → 可见格数 == 核数")
    }

    // 边界：0 核也有 1 行高度（空态一格「—」），1 核只有 1 行
    assertEqual(SystemDetailFormatting.heatContentHeight(coreCount: 0,
                                                         cellSize: cellSize, gap: gap), 26,
                "空态 1 行高度")
    assertEqual(SystemDetailFormatting.heatCellFrames(coreCount: 0,
                                                      cellSize: cellSize, gap: gap).isEmpty, true,
                "0 核 → 无格位（视图单独画一格「—」）")
}

private func testByteCountParts() {
    // 正常：拆成「数值 + 单位」（详情页事实行分开排版）
    let gpu = SystemDetailFormatting.byteCountParts(557_700_000)
    assertEqual(gpu.value, "531.9", "数值部分")
    assertEqual(gpu.unit, "MB", "单位部分")
    let bytes = SystemDetailFormatting.byteCountParts(512)
    assertEqual(bytes.value, "512", "B 级数值")
    assertEqual(bytes.unit, "B", "B 级单位")

    // 边界 / 异常：不可得时连单位一起撤
    let missing = SystemDetailFormatting.byteCountParts(nil)
    assertEqual(missing.value, "—", "nil → 「—」")
    assertEqual(missing.unit, nil, "nil → 无单位，避免「— MB」")
    assertEqual(SystemDetailFormatting.byteCountParts(Double.nan).value, "—", "NaN → 「—」")
}

private func testSampleIntervalText() {
    assertEqual(SystemDetailFormatting.sampleIntervalText(1), "1 秒", "默认 1 秒")
    assertEqual(SystemDetailFormatting.sampleIntervalText(0.5), "0.5 秒", "半秒")
    assertEqual(SystemDetailFormatting.sampleIntervalText(2), "2 秒", "整秒不带小数位")

    // 边界 / 异常
    assertEqual(SystemDetailFormatting.sampleIntervalText(nil), "—", "nil 显示「—」")
    assertEqual(SystemDetailFormatting.sampleIntervalText(0), "—", "0 不合法")
    assertEqual(SystemDetailFormatting.sampleIntervalText(-1), "—", "负数不合法")
    assertEqual(SystemDetailFormatting.sampleIntervalText(.nan), "—", "NaN 不合法")
}
