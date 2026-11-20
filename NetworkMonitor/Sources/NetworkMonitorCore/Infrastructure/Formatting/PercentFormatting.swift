import Foundation

// MARK: - 百分比口径（全项目唯一实现）

/// 百分比文本的唯一实现处 —— 系统页、Token 页、额度页与日志共用
///
/// 收敛前同一件事各有各的写法（是否钳制、保留几位、带不带 % 号彼此漂移）：
/// `SystemMetricsFormatting.percentText` / `SystemDetailFormatting.percentNumberText` /
/// `SystemDetailFormatting.compactPercentText` / `TokenFormat.percent` / `TokenFormatting.percent`。
/// 这里只做算术与文本拼接，不含任何视图假设，因此 TestRunner 能直接断言。
public enum PercentFormatting {

    // MARK: 钳制

    /// 0…1 钳制；非有限值（NaN / ±无穷）一律归 0
    ///
    /// 采样失败时调用方不该看到 "nan%" 或越界读数，兜底放在唯一入口而不是各个调用点。
    public static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    // MARK: 整数口径

    /// 整数百分比，不带 % 号：0.005 → "1"、0.004 → "0"
    ///
    /// 详情页的大号数字与单位分开排版（数字 19pt、% 号 9.5pt），所以这里只出数字。
    public static func integerNumber(_ ratio: Double) -> String {
        String(Int((clampedUnit(ratio) * 100).rounded()))
    }

    /// 整数百分比，带 % 号：0.005 → "1%"、1.5 → "100%"
    ///
    /// 卡片与状态带这类「一位数宽」的位置用整数，避免小数位让相邻读数左右晃。
    public static func integer(_ ratio: Double) -> String {
        integerNumber(ratio) + "%"
    }

    // MARK: 小数口径

    /// 一位小数，整数时不带小数位：0.012875 → "1.3%"、0.40 → "40%"
    ///
    /// 0.05 的阈值来自改造前详情页的口径：四舍五入到整数后差值小于 0.05 就按整数出，
    /// 这样 64.0 写成 "64%" 而不是 "64.0%"——同列读数带不带 .0 会让版式发虚。
    public static func compact(_ ratio: Double) -> String {
        let percent = clampedUnit(ratio) * 100
        let rounded = percent.rounded()
        if abs(percent - rounded) < 0.05 {
            return String(Int(rounded)) + "%"
        }
        return String(format: "%.1f%%", percent)
    }

    /// 固定小数位，入参是比例（0…1）：0.095 → "9.5%"、decimals: 2 → "9.50%"
    ///
    /// 刻意不钳制：Token 页的占比由「分子 / 分母」算出，越界说明数据本身有问题，
    /// 原样暴露（负数带符号）比悄悄削平成 0% / 100% 更容易发现口径错误。
    public static func fixed(_ ratio: Double, decimals: Int = 1) -> String {
        String(format: "%.\(max(0, decimals))f%%", ratio * 100)
    }

    /// 固定小数位，入参已经是百分比数值：298.4 → "298.4%"
    ///
    /// 进程 CPU 是多核累加的，可以 >100%，削平会让排行读数全部顶格、失去排序意义。
    /// 只把负值与非有限值归 0：内核不会给负占用，出现即异常，显示 0 比 "-3.0%" 更像占位。
    public static func unclampedFixed(_ percent: Double, decimals: Int = 1) -> String {
        let value = percent.isFinite ? max(0, percent) : 0
        return String(format: "%.\(max(0, decimals))f%%", value)
    }
}
