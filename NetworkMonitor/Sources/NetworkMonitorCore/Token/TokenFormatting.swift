import Foundation

// MARK: - Token 页数值格式化（与 Core 的 TokenFormat 分工：Core 管跨页通用口径，这里管本页排版口径）

/// 本页专用格式化：tok 缩写、百分比、时长、增量方向
package enum TokenFormatting {

    /// tok 缩写：1.30M / 225.2K / 398
    package static func tokens(_ value: Int) -> String {
        abbreviated(Double(value))
    }

    /// 浮点 tok 缩写（日均等中间量）
    ///
    /// 化简规则收敛在 `NumberUnits.scale`：设置页「数值单位」切到中文后，
    /// 这里自动给出 `1.6亿` / `265万`，本页视图无需改代码。
    package static func abbreviated(_ value: Double) -> String {
        NumberUnits.scale(value).text
    }

    /// 拆成「数值 + 单位」两段（分族卡的数字字号不同；单位段带 " tok" 后缀）
    package static func splitTokens(_ value: Int) -> (number: String, unit: String) {
        let scaled = NumberUnits.scale(Double(value))
        guard let unit = scaled.unit else { return (scaled.number, "tok") }
        return (scaled.number, unit + " tok")
    }

    /// 一位小数
    package static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// 占比：0.095 → 9.5%
    package static func percent(_ fraction: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", fraction * 100) + "%"
    }

    /// 千分位
    package static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// 同比文案：↑+19.4% / ↓ 3.2% / 持平 / —
    package static func delta(current: Int, previous: Int) -> (text: String, up: Bool)? {
        guard previous > 0 else { return nil }
        let ratio = (Double(current) - Double(previous)) / Double(previous) * 100
        if abs(ratio) < 0.05 { return ("持平", true) }
        let sign = ratio >= 0 ? "↑ +" : "↓ "
        return (sign + decimal(abs(ratio)) + "%", ratio >= 0)
    }

    /// 当前时刻 HH:mm（上海时区）
    package static func clock(_ now: Date) -> String {
        let components = HarnessTokenTimeWindow.calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// 月日：10-24
    package static func mmdd(_ dayKey: String) -> String {
        TokenFormat.mmdd(dayKey)
    }

}
