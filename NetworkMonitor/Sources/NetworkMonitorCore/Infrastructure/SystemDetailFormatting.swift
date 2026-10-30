import Foundation

// MARK: - 二级详情页展示口径（纯逻辑）

/// 四个二级详情页（CPU / GPU / 内存 / 磁盘）的数值格式化 — 不依赖 AppKit
///
/// 与 `SystemMetricsFormatting` 分开：那边是卡片与采样口径（百分比 / 速率 / 容量比 / P·E 分组），
/// 这边只服务详情页的大号数值、每核均值、分段占比与容量行。两者都是纯函数，供面板与 TestRunner 共用。
public enum SystemDetailFormatting {

    /// 不可用占位
    public static let placeholder = "—"

    // MARK: 百分比

    /// 百分比数值（不带 % 号）— 详情页大号数字与单位分开排版
    public static func percentNumberText(_ ratio: Double) -> String {
        "\(Int((clampedUnit(ratio) * 100).rounded()))"
    }

    /// 紧凑百分比：一位小数，整数时不带小数位（0.012875 → "1.3%"，0.40 → "40%"）
    public static func compactPercentText(_ ratio: Double) -> String {
        let percent = clampedUnit(ratio) * 100
        let rounded = percent.rounded()
        if abs(percent - rounded) < 0.05 {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", percent)
    }

    /// 一组比例的平均值（每核均值）；空数组或全部非法 → "—"
    ///
    /// 非法值（NaN / 无穷 / 负数）不参与平均，避免一个脏点拉低整组读数。
    public static func meanCompactPercentText(_ values: [Double]) -> String {
        var sum = 0.0
        var count = 0
        for value in values where value.isFinite && value >= 0 {
            sum += min(value, 1)
            count += 1
        }
        guard count > 0 else { return placeholder }
        return compactPercentText(sum / Double(count))
    }

    // MARK: 容量

    /// 容量（字节）→ "10.3 GB"；1024 进位，B 级取整、K 以上 1 位小数；nil → "—"
    public static func byteCountText(_ bytes: UInt64?) -> String {
        guard let bytes else { return placeholder }
        return byteCountText(Double(bytes))
    }

    /// 容量（字节，Double 入口：GPU 显存等）；非有限或负数 → "—"
    public static func byteCountText(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite else { return placeholder }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = max(0, bytes)
        var index = 0
        while scaled >= 1024, index < units.count - 1 {
            scaled /= 1024
            index += 1
        }
        guard index > 0 else { return String(format: "%.0f %@", scaled, units[index]) }
        return String(format: "%.1f %@", scaled, units[index])
    }

    /// 无单位 GB 数值（1 位小数）— 内存四段行与详情页大号数字用
    public static func gigabyteValueText(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    /// 容量拆成「数值 + 单位」（详情页事实行要求数值与单位分开排版）
    public static func byteCountParts(_ bytes: Double?) -> (value: String, unit: String?) {
        let text = byteCountText(bytes)
        guard text != placeholder else { return (text, nil) }
        let parts = text.split(separator: " ", maxSplits: 1)
        return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : nil)
    }

    /// 「已用 / 总量」容量行："432.9 GB / 926.4 GB"
    public static func capacityPairText(used: UInt64, total: UInt64) -> String {
        byteCountText(used) + " / " + byteCountText(total)
    }

    /// 可用容量 = 总量 − 已用；已用超过总量时按 0（不出现负容量）
    public static func availableBytes(used: UInt64, total: UInt64) -> UInt64 {
        total > used ? total - used : 0
    }

    /// 分段占总量的整数百分比："11%"；总量 0 → "—"（不可得与「真的 0%」区分）
    public static func sharePercentText(part: UInt64, total: UInt64) -> String {
        guard total > 0 else { return placeholder }
        let ratio = min(1, Double(part) / Double(total))
        return "\(Int((ratio * 100).rounded()))%"
    }

    // MARK: 衍生状态

    /// GPU 当前状态（界面词）：0 → 「空闲」，> 0 → 「使用中」；非有限 → "—"
    public static func gpuStateText(utilization: Double) -> String {
        guard utilization.isFinite else { return placeholder }
        return utilization <= 0 ? "空闲" : "使用中"
    }

    /// 每核热力档位：0 常规（< 10%）/ 1 中档（< 30%）/ 2 高热（≥ 30%）
    ///
    /// 非有限值按 0 档（与 `SystemPaneView.clamp` 同一兜底口径）。
    public static func heatTier(_ usage: Double) -> Int {
        let value = clampedUnit(usage)
        if value >= 0.30 { return 2 }
        if value >= 0.10 { return 1 }
        return 0
    }

    /// 每核热力格里的百分比文本：< 10% 保留一位小数（0.4 → "0.4"），≥ 10% 取整（38 → "38"）
    ///
    /// 与原型一致：P 核多数是个位数（0.7 / 1.2 这类一位小数才有区分度），E 核是两位数。
    public static func heatPercentText(_ usage: Double) -> String {
        let percent = clampedUnit(usage) * 100
        guard percent < 10 else { return String(Int(percent.rounded())) }
        let tenths = (percent * 10).rounded() / 10
        if abs(tenths - tenths.rounded()) < 0.05 {
            return String(Int(tenths.rounded()))
        }
        return String(format: "%.1f", tenths)
    }

    // MARK: 每核热力格布局

    /// 每行格子数 — 与定稿原型一致：10 核排成「9 + 1」两行
    public static let heatColumns = 9

    /// 网格行数 = ceil(核数 / 9)，至少 1 行（空态也占一行，卡片不塌）
    ///
    /// **必须是向上取整**：10 / 9 整除去掉余数会得到 1 行，第 10 格（E1）就被裁在容器外。
    public static func heatRowCount(_ coreCount: Int) -> Int {
        let count = max(0, coreCount)
        return max(1, (count + heatColumns - 1) / heatColumns)
    }

    /// 单格槽位（0 基行列）
    public struct HeatCellSlot: Equatable, Sendable {
        /// 行
        public let row: Int
        /// 列
        public let column: Int
    }

    /// 第 index 个核所在的槽位
    public static func heatCellSlot(index: Int) -> HeatCellSlot {
        let safe = max(0, index)
        return HeatCellSlot(row: safe / heatColumns, column: safe % heatColumns)
    }

    /// 单格位置与尺寸（与视图共用同一份布局算术，测试可复核）
    public struct HeatCellFrame: Equatable, Sendable {
        /// 距网格左上角的 x
        public let minX: Double
        /// 距网格左上角的 y
        public let minY: Double
        /// 格宽
        public let width: Double
        /// 格高
        public let height: Double
    }

    /// 全部格位：格子数量恒等于核数（可见格数 == n），且都落在 rowCount 行的网格内
    public static func heatCellFrames(coreCount: Int,
                                      cellSize: Double,
                                      gap: Double) -> [HeatCellFrame] {
        let count = max(0, coreCount)
        let step = cellSize + gap
        return (0..<count).map { index in
            let slot = heatCellSlot(index: index)
            return HeatCellFrame(minX: Double(slot.column) * step,
                                 minY: Double(slot.row) * step,
                                 width: cellSize,
                                 height: cellSize)
        }
    }

    /// 网格内容高度（行数 × 格高 + 行间间距）
    public static func heatContentHeight(coreCount: Int, cellSize: Double, gap: Double) -> Double {
        let rows = heatRowCount(coreCount)
        return Double(rows) * cellSize + Double(rows - 1) * gap
    }

    /// 采样周期文本："1 秒" / "0.5 秒"；nil、非正、非有限 → "—"
    public static func sampleIntervalText(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return placeholder }
        let rounded = (seconds * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded())) 秒"
        }
        return String(format: "%.1f 秒", rounded)
    }

    /// 0...1 钳制；非有限值归 0
    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
