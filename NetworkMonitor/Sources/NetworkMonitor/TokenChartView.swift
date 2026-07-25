import SwiftUI
import Charts
import NetworkMonitorCore

// MARK: - Token 用量图表

/// 每小时 Token 用量柱状图
struct TokenHourlyChartView: View {
    let data: [HourlyTokenUsage]

    var body: some View {
        if data.isEmpty {
            Text("暂无数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 140)
        } else {
            Chart(data, id: \.hour) { entry in
                BarMark(
                    x: .value("小时", "\(entry.hour)时"),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue.opacity(0.7))
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        Text(formatToken(value))
                            .font(.caption2)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 140)
            .padding(.vertical, 4)
        }
    }

    private func formatToken(_ value: AxisValue) -> String {
        guard let count = value.as(Int.self) else { return "" }
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }
}

/// 近 7 日 Token 用量柱状图
struct TokenHistoryChartView: View {
    let data: [DailyTokenUsage]

    var body: some View {
        if data.isEmpty {
            Text("暂无历史数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 140)
        } else {
            Chart(data, id: \.date) { entry in
                BarMark(
                    x: .value("日期", shortDate(entry.date)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue.opacity(0.7))
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        Text(formatToken(value))
                            .font(.caption2)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 140)
            .padding(.vertical, 4)
        }
    }

    private func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        return "\(Int(parts[1])!)/\(Int(parts[2])!)"
    }

    private func formatToken(_ value: AxisValue) -> String {
        guard let count = value.as(Int.self) else { return "" }
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }
}
