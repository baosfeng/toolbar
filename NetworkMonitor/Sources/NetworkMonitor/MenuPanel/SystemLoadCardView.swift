import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// 首屏五卡：压力
// 负载三线图 + 进程 Top-2 —— 压力是「就绪队列多长」，进程榜是「谁在吃 CPU」，同卡上下排布。

// MARK: - 压力卡

/// 压力卡 —— 负载三线图 + 进程 Top-2；卡头右端「全部 ›」进压力详情
///
/// 负载是「就绪队列多长」、进程榜是「谁在吃 CPU」，两者合起来才叫压力，故同卡上下排布。
/// 进程榜沿用 DrawnRowList 的同一套行口径（specs + rowStyle），只是不建行列表视图。
final class SystemLoadCardView: SystemCardView {

    private static let chartHeight: CGFloat = 34
    private static let contentGap: CGFloat = 4
    private static let rowHeight: CGFloat = 13
    private static let rowSpacing: CGFloat = 2
    /// 首屏固定两行（Top-3 收到 Top-2 是版2 的定稿）—— 榜单条数也被页级刷新复用
    static let rowLimit = 2
    private static let legendFont = MenuPanelStyle.smallValueFont

    private var shortText = SystemPaneFormat.placeholder
    private var mediumText = SystemPaneFormat.placeholder
    private var longText = SystemPaneFormat.placeholder
    private var coreCount = 0
    private var processRows: [SystemProcessListView.Row] = []

    /// 1 / 5 / 15 分钟序列
    var shortValues: [Double] = [] { didSet { needsDisplay = true } }
    var mediumValues: [Double] = [] { didSet { needsDisplay = true } }
    var longValues: [Double] = [] { didSet { needsDisplay = true } }

    override var contentHeight: CGFloat {
        Self.chartHeight + Self.contentGap
            + DrawnRowLayout.contentHeight(rowCount: Self.rowLimit,
                                          rowHeight: Self.rowHeight,
                                          rowSpacing: Self.rowSpacing)
    }

    /// 刷新三值与核数标记（nil = 空态）
    func update(_ snapshot: LoadSnapshot?) {
        guard let snapshot else {
            shortText = SystemPaneFormat.placeholder
            mediumText = SystemPaneFormat.placeholder
            longText = SystemPaneFormat.placeholder
            coreCount = 0
            caption = SystemPaneFormat.placeholder
            headAccessory = makeLegend()
            needsDisplay = true
            return
        }
        shortText = Self.loadText(snapshot.load1)
        mediumText = Self.loadText(snapshot.load5)
        longText = Self.loadText(snapshot.load15)
        coreCount = max(0, snapshot.coreCount)
        // 卡头已有三枚负载数值，右侧只留「/10」这种极短核数标记（「核」字进 toolTip）
        caption = snapshot.coreCount > 0 ? "/\(snapshot.coreCount)" : SystemPaneFormat.placeholder
        headAccessory = makeLegend()
        needsDisplay = true
    }

    /// 刷新进程 Top-2（空 = 不可得态：两行都写「—」+ 空描边条）
    func update(processRows rows: [SystemProcessListView.Row]) {
        processRows = rows
        needsDisplay = true
    }

    override var contentAccessibilityText: String {
        let rows = SystemProcessListView.specs(rows: processRows, capacity: Self.rowLimit)
        let rowText = rows.map { $0.title + " " + $0.value }.joined(separator: "，")
        return "负载 1m \(shortText)，5m \(mediumText)，15m \(longText)，\(rowText)"
    }

    /// 负载原值：2 位小数（与原型一致），非有限值显示「—」
    private static func loadText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return SystemPaneFormat.placeholder }
        return String(format: "%.2f", max(0, value))
    }

    override func drawContent(in rect: CGRect) {
        let chartRect = CGRect(x: rect.minX, y: rect.minY,
                               width: rect.width, height: Self.chartHeight)
        let peak = (shortValues + mediumValues + longValues).max() ?? 0
        SystemChartDrawing.drawLoadChart(short: shortValues,
                                         medium: mediumValues,
                                         long: longValues,
                                         coreCount: coreCount,
                                         axisMaximum: SystemCardLayout.loadAxisMaximum(coreCount: coreCount,
                                                                                       peak: peak),
                                         in: chartRect,
                                         shortColor: SystemPaneStyle.loadShort,
                                         mediumColor: SystemPaneStyle.loadMedium,
                                         longColor: SystemPaneStyle.loadLong,
                                         referenceColor: SystemPaneStyle.loadCoreReference,
                                         trackColor: SystemPalette.track)
        var rowY = chartRect.maxY + Self.contentGap
        let style = SystemProcessListView.rowStyle
        let specs = SystemProcessListView.specs(rows: processRows, capacity: Self.rowLimit)
        for spec in specs {
            style.draw(spec, in: CGRect(x: rect.minX, y: rowY,
                                        width: rect.width, height: Self.rowHeight))
            rowY += Self.rowHeight + Self.rowSpacing
        }
    }

    /// 卡头图例：1m / 5m / 15m 三枚「线形色块 + 数值」（色块用线段而非方点，暗示对应曲线是线）
    private func makeLegend() -> DrawnReadoutRun {
        func item(_ color: NSColor, _ text: String) -> [DrawnReadoutPiece] {
            [
                .swatch(color: color, width: 7, height: 2, radius: 1),
                SystemDrawnText.piece(text, font: Self.legendFont,
                                      color: SystemPalette.foregroundSecondary),
            ]
        }
        return DrawnReadoutRun(
            groups: [item(SystemPaneStyle.loadShort, shortText),
                     item(SystemPaneStyle.loadMedium, mediumText),
                     item(SystemPaneStyle.loadLong, longText)],
            innerGap: 2,
            groupGap: 6)
    }
}
