import SwiftUI
import Charts
import NetworkMonitorCore

// MARK: - 模型占比环形图

struct TokenModelPieChart: View {
    let byModel: [TokenUsageByModel]

    private var totalTokens: Int { byModel.reduce(0) { $0 + $1.totalTokens } }

    var body: some View {
        if byModel.isEmpty {
            Text("暂无数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 100)
        } else {
            Chart(byModel, id: \.model) { entry in
                SectorMark(
                    angle: .value("Token", entry.totalTokens),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("模型", shortName(entry.model)))
                .cornerRadius(3)
                .annotation(position: .overlay) {
                    if Double(entry.totalTokens) / Double(max(totalTokens, 1)) > 0.12 {
                        Text("\(Int(Double(entry.totalTokens) / Double(max(totalTokens, 1)) * 100))%")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(byModel, id: \.model) { entry in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(colorForModel(entry.model))
                                .frame(width: 7, height: 7)
                            Text(shortName(entry.model))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 100)
            .padding(.vertical, 4)
        }
    }

    private func shortName(_ model: String) -> String {
        if model.lowercased().contains("gpt-4o") { return "GPT-4o" }
        if model.lowercased().contains("gpt-4") { return "GPT-4" }
        if model.lowercased().contains("claude-3.5") || model.lowercased().contains("claude-35") { return "Claude 3.5" }
        if model.lowercased().contains("claude") { return "Claude" }
        if model.lowercased().contains("gemini") { return "Gemini" }
        if model.lowercased().contains("deepseek") { return "DeepSeek" }
        if model.count > 10 { return String(model.prefix(8)) + "…" }
        return model
    }

    private func colorForModel(_ model: String) -> Color {
        let name = model.lowercased()
        if name.contains("gpt") { return .green }
        if name.contains("claude") { return .orange }
        if name.contains("gemini") { return .blue }
        if name.contains("deepseek") { return .purple }
        return .gray
    }
}

// MARK: - 每小时 Token 折线面积图

struct TokenHourlyChartView: View {
    let data: [HourlyTokenUsage]
    let maxTokens: Int

    init(data: [HourlyTokenUsage]) {
        self.data = data
        self.maxTokens = data.map(\.totalTokens).max() ?? 1
    }

    var body: some View {
        if data.isEmpty {
            Text("暂无数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 150)
        } else {
            Chart(data, id: \.hour) { entry in
                // 面积填充
                AreaMark(
                    x: .value("小时", hourLabel(entry.hour)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue.opacity(0.12))

                // 折线
                LineMark(
                    x: .value("小时", hourLabel(entry.hour)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                // 数据点
                PointMark(
                    x: .value("小时", hourLabel(entry.hour)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue)
                .symbolSize(CGSize(width: 5, height: 5))
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
            .frame(height: 150)
            .padding(.vertical, 4)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        "\(hour)时"
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

// MARK: - 近 7 日 Token 折线面积图

struct TokenHistoryChartView: View {
    let data: [DailyTokenUsage]

    var body: some View {
        if data.isEmpty {
            Text("暂无历史数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 150)
        } else {
            Chart(data, id: \.date) { entry in
                // 面积填充
                AreaMark(
                    x: .value("日期", shortDate(entry.date)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue.opacity(0.12))

                // 折线
                LineMark(
                    x: .value("日期", shortDate(entry.date)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                // 数据点
                PointMark(
                    x: .value("日期", shortDate(entry.date)),
                    y: .value("Token", entry.totalTokens)
                )
                .foregroundStyle(.blue)
                .symbolSize(CGSize(width: 6, height: 6))
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
            .frame(height: 150)
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
