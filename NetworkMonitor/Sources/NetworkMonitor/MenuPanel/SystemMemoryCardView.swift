import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// 首屏五卡：内存 / 磁盘
// 堆叠条与容量读数类卡片 —— 只写各自的数据与内容区绘制，卡底 / 卡头由 SystemCardView 统一绘制。
// CPU / GPU 卡在 SystemDrawnText.swift，压力卡在 SystemLoadCardView.swift。

// MARK: - 内存卡

/// 内存卡 —— 只留四段堆叠条 + 卡头压力徽标（四段数值下沉到内存详情）
final class SystemMemoryCardView: SystemCardView {

    private static let barHeight: CGFloat = 9
    private static let dotSize: CGFloat = 8

    private var segments: [SystemBarSegment] = []
    private var total: Double = 0
    private var pressure: SystemPressureDotView.Level = .unknown

    override var contentHeight: CGFloat { Self.barHeight }

    /// 刷新四段条与压力徽标（nil / 总量为 0 = 空态：整条只剩轨道）
    func update(_ snapshot: MemorySnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            segments = []
            total = 0
            pressure = .unknown
            headAccessory = Self.pressureRun(.unknown)
            caption = SystemPaneFormat.placeholder
            needsDisplay = true
            return
        }
        let totalBytes = Double(snapshot.total)
        let used = min(Double(snapshot.used), totalBytes)
        let wired = min(Double(snapshot.wired), used)
        let compressed = min(Double(snapshot.compressed), max(0, used - wired))
        let active = max(0, used - wired - compressed)
        let free = max(0, totalBytes - used)
        total = totalBytes
        if snapshot.wired > 0 || snapshot.active > 0 {
            segments = [
                SystemBarSegment(value: wired, color: SystemPaneStyle.memoryWired),
                SystemBarSegment(value: active, color: SystemPaneStyle.memoryActive),
                SystemBarSegment(value: compressed, color: SystemPaneStyle.memoryCompressed),
                SystemBarSegment(value: free, color: .clear),
            ]
        } else {
            // 老快照未拆分 wired / active：非压缩已用合并为一段，仍保持四段槽位形状
            segments = [
                SystemBarSegment(value: used - compressed, color: SystemPaneStyle.memoryActive),
                SystemBarSegment(value: compressed, color: SystemPaneStyle.memoryCompressed),
                SystemBarSegment(value: free, color: .clear),
            ]
        }
        pressure = SystemPaneView.level(for: snapshot.pressure)
        headAccessory = Self.pressureRun(pressure)
        caption = SystemDetailFormatting.capacityPairText(used: snapshot.used, total: snapshot.total)
        needsDisplay = true
    }

    override var contentAccessibilityText: String { "内存 " + caption }

    override func drawContent(in rect: CGRect) {
        SystemChartDrawing.drawStackedBar(segments: segments,
                                         total: total,
                                         pressureStroke: SystemChartDrawing.pressureStrokeColor(pressure),
                                         gapColor: washColor,
                                         in: rect)
    }

    /// 压力徽标：8pt 圆点（正常绿 / 警告琥珀 / 严重红 / 未知灰）
    private static func pressureRun(_ level: SystemPressureDotView.Level) -> DrawnReadoutRun {
        let color: NSColor
        switch level {
        case .normal: color = SystemPalette.ok
        case .warning: color = SystemPalette.warn
        case .critical: color = SystemPalette.danger
        case .unknown: color = SystemPalette.track
        }
        return DrawnReadoutRun(groups: [[.dot(color: color, size: dotSize, ringColor: nil)]])
    }
}

// MARK: - 磁盘卡

/// 磁盘卡 —— 版2 压成单行：卡头「忙 + 繁忙度微条」+ 右侧容量 + 「›」
final class SystemDiskCardView: SystemCardView {

    private static let trackWidth: CGFloat = 30
    private static let trackHeight: CGFloat = 3

    private var busyText = SystemPaneFormat.placeholder
    private var busyColor: NSColor = SystemPalette.meta
    private var busyFraction: Double = 0

    /// 刷新繁忙度（nil = 不可得态：「—」+ 空条）
    func update(_ snapshot: DiskSnapshot?) {
        guard let snapshot, snapshot.total > 0 else {
            busyText = SystemPaneFormat.placeholder
            busyColor = SystemPalette.meta
            busyFraction = 0
            caption = SystemPaneFormat.placeholder
            headAccessory = makeBusyRun()
            needsDisplay = true
            return
        }
        let available = snapshot.busyFraction != nil
        busyText = available ? SystemPaneFormat.percent(snapshot.busyFraction)
            : SystemPaneFormat.placeholder
        busyColor = available ? SystemPalette.diskInk : SystemPalette.meta
        busyFraction = available ? SystemPaneFormat.unitFraction(snapshot.busyFraction) : 0
        caption = SystemDetailFormatting.capacityPairText(used: snapshot.used, total: snapshot.total)
        headAccessory = makeBusyRun()
        needsDisplay = true
    }

    override var contentAccessibilityText: String {
        "忙 " + busyText + "，" + caption
    }

    /// 卡头「忙 + 比例 + 30pt 微条」（微条是本页唯一一处「读数后面紧跟条」的排法）
    private func makeBusyRun() -> DrawnReadoutRun {
        DrawnReadoutRun(
            groups: [[
                SystemDrawnText.piece("忙", font: SystemPaneStyle.microFont,
                                      color: SystemPalette.meta),
                SystemDrawnText.piece(busyText, font: MenuPanelStyle.smallValueFont,
                                      color: busyColor),
                .track(fraction: busyFraction,
                       width: Self.trackWidth,
                       height: Self.trackHeight,
                       track: MenuPanelStyle.trackColor,
                       fill: SystemPalette.disk),
            ]],
            innerGap: 4)
    }
}

