import AppKit
import DGCharts
import NetworkMonitorCore

// MARK: - 一级菜单 24 小时柱状图

/// 24 小时迷你柱状图 — 直接嵌入一级菜单
final class MiniMenuChartView: BarChartView {

    init(data: [HourlyTokenUsage]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
        setup(data: data)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    private func setup(data: [HourlyTokenUsage]) {
        // 基本设置
        chartDescription.enabled = false
        legend.enabled = false
        setScaleEnabled(false)
        dragEnabled = false
        pinchZoomEnabled = false
        doubleTapToZoomEnabled = false
        highlightPerTapEnabled = false
        highlightPerDragEnabled = false

        // 网格
        xAxis.drawGridLinesEnabled = false
        xAxis.drawAxisLineEnabled = false
        xAxis.labelPosition = .bottom
        xAxis.labelFont = NSFont.systemFont(ofSize: 8)
        xAxis.labelTextColor = NSColor.secondaryLabelColor
        xAxis.setLabelCount(7, force: false)
        xAxis.valueFormatter = HourAxisFormatter()

        leftAxis.drawGridLinesEnabled = false
        leftAxis.drawAxisLineEnabled = false
        leftAxis.drawLabelsEnabled = false

        rightAxis.enabled = false

        // 数据
        var entries: [BarChartDataEntry] = []
        for entry in data {
            entries.append(BarChartDataEntry(x: Double(entry.hour), y: Double(entry.totalTokens)))
        }

        let set = BarChartDataSet(entries: entries, label: "")
        set.colors = [NSColor.systemBlue.withAlphaComponent(0.7)]
        set.highlightColor = NSColor.clear
        set.drawValuesEnabled = true
        set.valueFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)
        set.valueTextColor = NSColor.secondaryLabelColor
        set.valueFormatter = TokenValueFormatter()

        let barData = BarChartData(dataSet: set)
        barData.barWidth = 0.7
        self.data = barData

        // 圆角效果

        // 背景透明
        backgroundColor = NSColor.clear
        gridBackgroundColor = NSColor.clear
        drawGridBackgroundEnabled = false

        animate(yAxisDuration: 0.3, easingOption: .easeOutCubic)
    }
}

// MARK: - 二级菜单 7 日柱状图

/// 7 日迷你柱状图 — 嵌入二级菜单
final class MiniHistoryMenuChartView: BarChartView {

    init(data: [DailyTokenUsage]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 100))
        setup(data: data)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    private func setup(data: [DailyTokenUsage]) {
        chartDescription.enabled = false
        legend.enabled = false
        setScaleEnabled(false)
        dragEnabled = false
        pinchZoomEnabled = false
        doubleTapToZoomEnabled = false
        highlightPerTapEnabled = false

        xAxis.drawGridLinesEnabled = false
        xAxis.drawAxisLineEnabled = false
        xAxis.labelPosition = .bottom
        xAxis.labelFont = NSFont.systemFont(ofSize: 8)
        xAxis.labelTextColor = NSColor.secondaryLabelColor
        xAxis.setLabelCount(data.count, force: true)
        xAxis.valueFormatter = DateAxisFormatter(data: data)

        leftAxis.drawGridLinesEnabled = false
        leftAxis.drawAxisLineEnabled = false
        leftAxis.drawLabelsEnabled = false
        rightAxis.enabled = false

        var entries: [BarChartDataEntry] = []
        for (i, entry) in data.enumerated() {
            entries.append(BarChartDataEntry(x: Double(i), y: Double(entry.totalTokens)))
        }

        let set = BarChartDataSet(entries: entries, label: "")
        set.colors = [NSColor.systemBlue.withAlphaComponent(0.7)]
        set.highlightColor = NSColor.clear
        set.drawValuesEnabled = true
        set.valueFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)
        set.valueTextColor = NSColor.secondaryLabelColor
        set.valueFormatter = TokenValueFormatter()

        let barData = BarChartData(dataSet: set)
        barData.barWidth = 0.6
        self.data = barData

        backgroundColor = NSColor.clear
        gridBackgroundColor = NSColor.clear
        drawGridBackgroundEnabled = false

        animate(yAxisDuration: 0.3, easingOption: .easeOutCubic)
    }
}

// MARK: - 轴格式化器

private final class HourAxisFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let h = Int(value)
        return "\(h)"
    }
}

private final class DateAxisFormatter: AxisValueFormatter {
    let labels: [String]
    init(data: [DailyTokenUsage]) {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        labels = data.map { entry in
            let parts = entry.date.split(separator: "-")
            guard parts.count == 3 else { return entry.date }
            return "\(Int(parts[1])!)/\(Int(parts[2])!)"
        }
    }
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let idx = Int(value)
        guard idx >= 0, idx < labels.count else { return "" }
        return labels[idx]
    }
}

// MARK: - 数据值格式化器

private final class TokenValueFormatter: ValueFormatter {
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        let c = Int(value)
        if c == 0 { return "" }
        if c >= 100_000_000 { return String(format: "%.1f亿", Double(c) / 100_000_000) }
        if c >= 10_000 { return String(format: "%.0f万", Double(c) / 10_000) }
        return "\(c)"
    }
}
