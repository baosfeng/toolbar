import SwiftUI
import Charts
import NetworkMonitorCore

// MARK: - 模型占比环形图

struct TokenModelPieChart: View {
    let byModel: [TokenUsageByModel]

    private var totalTokens: Int { byModel.reduce(0) { $0 + $1.totalTokens } }

    var body: some View {
        if byModel.isEmpty {
            Text("暂无数据").font(.caption).foregroundStyle(.secondary).frame(height: 100)
        } else {
            Chart(byModel, id: \.model) { entry in
                SectorMark(angle: .value("Token", entry.totalTokens),
                           innerRadius: .ratio(0.55), angularInset: 1.5)
                    .foregroundStyle(by: .value("模型", shortName(entry.model)))
                    .cornerRadius(3)
                    .annotation(position: .overlay) {
                        if Double(entry.totalTokens) / Double(max(totalTokens, 1)) > 0.12 {
                            Text("\(Int(Double(entry.totalTokens) / Double(max(totalTokens, 1)) * 100))%")
                                .font(.caption2.bold()).foregroundStyle(.white)
                        }
                    }
            }
            .chartLegend(position: .bottom, spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(byModel, id: \.model) { entry in
                        HStack(spacing: 3) {
                            Circle().fill(colorForModel(entry.model)).frame(width: 7, height: 7)
                            Text(shortName(entry.model)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 100).padding(.vertical, 4)
        }
    }

    private func shortName(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("gpt-4o") { return "GPT-4o" }
        if m.contains("gpt-4") { return "GPT-4" }
        if m.contains("claude-3.5") || m.contains("claude-35") { return "Claude 3.5" }
        if m.contains("claude") { return "Claude" }
        if m.contains("gemini") { return "Gemini" }
        if m.contains("deepseek") { return "DeepSeek" }
        return model.count > 10 ? String(model.prefix(8)) + "…" : model
    }

    private func colorForModel(_ model: String) -> Color {
        let m = model.lowercased()
        if m.contains("gpt") { return .green }
        if m.contains("claude") { return .orange }
        if m.contains("gemini") { return .blue }
        if m.contains("deepseek") { return .purple }
        return .gray
    }
}

// MARK: - 迷你柱状图（嵌入二级菜单）

/// 迷你逐时柱状图 — 嵌入二级菜单
struct MiniHourlyChartView: View {
    let data: [HourlyTokenUsage]

    var body: some View {
        if data.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "clock").font(.title2).foregroundStyle(.tertiary)
                Text("暂无数据").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(data, id: \.hour) { entry in
                BarMark(x: .value("时", hourLabel(entry.hour)),
                        y: .value("Token", entry.totalTokens))
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel().font(.system(size: 8))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 7))
                }
            }
            .chartLegend(.hidden)
            .padding(4)
        }
    }

    private func hourLabel(_ hour: Int) -> String { "\(hour)" }
}

/// 迷你历史柱状图 — 嵌入二级菜单
struct MiniHistoryChartView: View {
    let data: [DailyTokenUsage]

    var body: some View {
        if data.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar").font(.title2).foregroundStyle(.tertiary)
                Text("暂无数据").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(data, id: \.date) { entry in
                BarMark(x: .value("日期", shortDate(entry.date)),
                        y: .value("Token", entry.totalTokens))
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel().font(.system(size: 8))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 7))
                }
            }
            .chartLegend(.hidden)
            .padding(4)
        }
    }

    private func shortDate(_ s: String) -> String {
        let p = s.split(separator: "-"); guard p.count == 3 else { return s }
        return "\(Int(p[1])!)/\(Int(p[2])!)"
    }
}

// MARK: - 完整面板图表（折线面积图）

/// 每小时 Token 折线面积图（面板用）
struct TokenHourlyChartView: View {
    let data: [HourlyTokenUsage]

    var body: some View {
        if data.isEmpty {
            Text("暂无数据").font(.caption).foregroundStyle(.secondary).frame(height: 150)
        } else {
            Chart(data, id: \.hour) { entry in
                AreaMark(x: .value("时", "\(entry.hour)时"), y: .value("Token", entry.totalTokens))
                    .foregroundStyle(.blue.opacity(0.1))
                LineMark(x: .value("时", "\(entry.hour)时"), y: .value("Token", entry.totalTokens))
                    .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("时", "\(entry.hour)时"), y: .value("Token", entry.totalTokens))
                    .foregroundStyle(.blue).symbolSize(CGSize(width: 5, height: 5))
            }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 150).padding(.vertical, 4)
        }
    }
}

/// 近 7 日 Token 折线面积图（面板用）
struct TokenHistoryChartView: View {
    let data: [DailyTokenUsage]

    var body: some View {
        if data.isEmpty {
            Text("暂无历史数据").font(.caption).foregroundStyle(.secondary).frame(height: 150)
        } else {
            Chart(data, id: \.date) { entry in
                AreaMark(x: .value("日期", shortDate(entry.date)), y: .value("Token", entry.totalTokens))
                    .foregroundStyle(.blue.opacity(0.1))
                LineMark(x: .value("日期", shortDate(entry.date)), y: .value("Token", entry.totalTokens))
                    .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("日期", shortDate(entry.date)), y: .value("Token", entry.totalTokens))
                    .foregroundStyle(.blue).symbolSize(CGSize(width: 5, height: 5))
            }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 150).padding(.vertical, 4)
        }
    }

    private func shortDate(_ s: String) -> String {
        let p = s.split(separator: "-"); guard p.count == 3 else { return s }
        return "\(Int(p[1])!)/\(Int(p[2])!)"
    }
}
