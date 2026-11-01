import Foundation
import NetworkMonitorCore

// MARK: - Token 页数值格式化（与 Core 的 TokenFormat 分工：Core 管跨页通用口径，这里管本页排版口径）

/// 本页专用格式化：tok 缩写、百分比、时长、增量方向
enum TokenFormatting {

    /// tok 缩写：1.30M / 225.2K / 398
    static func tokens(_ value: Int) -> String {
        abbreviated(Double(value))
    }

    /// 浮点 tok 缩写（日均等中间量）
    static func abbreviated(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000_000 { return trimmed(value / 1_000_000_000, decimals: 2) + "B" }
        if magnitude >= 1_000_000 { return trimmed(value / 1_000_000, decimals: 2) + "M" }
        if magnitude >= 1_000 { return trimmed(value / 1_000, decimals: 1) + "K" }
        return String(Int(value.rounded()))
    }

    /// 拆成「数值 + 单位」两段（分族卡的数字字号不同）
    static func splitTokens(_ value: Int) -> (number: String, unit: String) {
        let text = tokens(value)
        for suffix in ["B", "M", "K"] where text.hasSuffix(suffix) {
            return (String(text.dropLast()), suffix + " tok")
        }
        return (text, "tok")
    }

    /// 一位小数
    static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// 占比：0.095 → 9.5%
    static func percent(_ fraction: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", fraction * 100) + "%"
    }

    /// 千分位
    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// 同比文案：↑+19.4% / ↓ 3.2% / 持平 / —
    static func delta(current: Int, previous: Int) -> (text: String, up: Bool)? {
        guard previous > 0 else { return nil }
        let ratio = (Double(current) - Double(previous)) / Double(previous) * 100
        if abs(ratio) < 0.05 { return ("持平", true) }
        let sign = ratio >= 0 ? "↑ +" : "↓ "
        return (sign + decimal(abs(ratio)) + "%", ratio >= 0)
    }

    /// 当前时刻 HH:mm（上海时区）
    static func clock(_ now: Date) -> String {
        let components = HarnessTokenTimeWindow.calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// 月日：10-24
    static func mmdd(_ dayKey: String) -> String {
        TokenFormat.mmdd(dayKey)
    }

    /// 去掉多余尾零：1.50 → 1.5，10.00 → 10
    private static func trimmed(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
