import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 首屏五卡（整卡自绘，卡内零视图）
//
// 五张卡共用 SystemCardView（卡底 + 卡头 + 内容区钩子），按职责分三个文件：
// 本文件 = 文字取色 + CPU 卡 + GPU 卡；内存 / 磁盘卡在 SystemMemoryCardView.swift；
// 压力卡在 SystemLoadCardView.swift。几何口径走 SystemCardLayout（纯逻辑、可断言），
// 图上内容走 SystemChartDrawing（与二级详情页里的同名视图共用同一份绘制）。
// 改造前五卡内部共 113 个视图（连状态带 132 个），改造后卡内 0 个。

// MARK: - 首屏文字的取色

/// 首屏五卡的文字取色 —— 统一走 SystemCardView.labelText 的「原生标签等效色」
///
/// 改造前这些文字是 AppKit 标签（带 alpha 的色会合成两次），自绘只合成一次会偏浅；
/// 折算集中在这一处，卡内各处不再各自处理。
@MainActor
enum SystemDrawnText {

    /// 一段文字
    static func run(_ text: String, font: NSFont, color: NSColor) -> DrawnTextRun {
        DrawnTextRun(string: text, font: font, color: SystemCardView.labelText(color))
    }

    /// 读数条里的一段文字
    static func piece(_ text: String, font: NSFont, color: NSColor) -> DrawnReadoutPiece {
        .text(run(text, font: font, color: color))
    }
}

// MARK: - CPU 卡

/// CPU 卡 —— 卡内 23pt 总利用率 + 60 秒叠加面积图；卡头挂用户态 / 系统态两枚图例
final class SystemCPUCardView: SystemCardView {

    /// 面积图高度（改造前 SystemAreaChartView(height: 32)）
    private static let chartHeight: CGFloat = 32
    /// 大号读数行高（23pt 等宽粗体的行高）
    private static let heroLineHeight: CGFloat = 27
    /// 大号读数与面积图之间的间距（改造前 stack spacing 8）
    private static let heroGap: CGFloat = 8
    private static let heroValueFont = NSFont.monospacedDigitSystemFont(ofSize: 23, weight: .bold)
    private static let heroUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

    private var heroValue = SystemPaneFormat.placeholder
    private var heroUnit: String?
    private var heroColor: NSColor = SystemPalette.meta

    /// 60 秒总量序列（面积图顶层）
    var totalValues: [Double] = [] { didSet { needsDisplay = true } }
    /// 60 秒系统态序列（叠加带；与总量等长才叠加）
    var systemValues: [Double] = [] { didSet { needsDisplay = true } }

    override var contentHeight: CGFloat { Self.chartHeight }

    /// 刷新读数与卡头图例（nil = 空态：读数写「—」、两枚图例也写「—」）
    func update(_ snapshot: CPUSnapshot?) {
        guard let snapshot else {
            heroValue = SystemPaneFormat.placeholder
            heroUnit = nil
            heroColor = SystemPalette.meta
            headAccessory = Self.legend(total: nil, system: nil)
            caption = SystemPaneFormat.placeholder
            needsDisplay = true
            return
        }
        heroValue = SystemDetailFormatting.percentNumberText(snapshot.totalUsage)
        heroUnit = "%"
        heroColor = SystemPalette.cpuInk
        headAccessory = Self.legend(total: snapshot.totalUsage, system: snapshot.systemUsage)
        caption = SystemPaneView.coreSummary(snapshot)
        needsDisplay = true
    }

    override var contentAccessibilityText: String {
        let legend = headAccessory?.accessibilityText ?? ""
        return legend.isEmpty ? heroText : heroText + "，" + legend
    }

    private var heroText: String { heroValue + (heroUnit ?? "") }

    /// 大号读数（值 + 单位共基线；单位走次级色，与改造前同一套富文本拼接）
    private var heroAttributed: NSAttributedString {
        let text = NSMutableAttributedString(string: heroValue,
                                             attributes: [.font: Self.heroValueFont,
                                                          .foregroundColor: heroColor])
        if let unit = heroUnit, !unit.isEmpty {
            text.append(NSAttributedString(string: unit,
                                           attributes: [.font: Self.heroUnitFont,
                                                        .foregroundColor: SystemPalette.meta]))
        }
        return text
    }

    override func drawContent(in rect: CGRect) {
        let attributed = heroAttributed
        // 排版宽按 0.5pt 网格取整（与标签对齐矩形同源），面积图从它右侧 8pt 起
        let heroWidth = min(ceil(attributed.size().width * 2) / 2, rect.width)
        let heroRect = CGRect(x: rect.minX,
                              y: rect.maxY - Self.heroLineHeight,
                              width: heroWidth,
                              height: Self.heroLineHeight)
        attributed.draw(with: heroRect,
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                        context: nil)
        let chartX = rect.minX + heroWidth + Self.heroGap
        let chartRect = CGRect(x: chartX,
                               y: rect.minY,
                               width: max(rect.maxX - chartX, 0),
                               height: rect.height)
        SystemChartDrawing.drawAreaChart(values: totalValues,
                                         overlayValues: systemValues,
                                         in: chartRect,
                                         lineColor: SystemPalette.cpu,
                                         overlayColor: SystemPaneStyle.systemUsageBand,
                                         fixedMaximum: nil,
                                         gridColor: SystemPalette.grid)
    }

    /// 卡头图例：用户态 / 系统态两枚「色块 + 数值」（两者取整后必须凑得出总量）
    private static func legend(total: Double?, system: Double?) -> DrawnReadoutRun {
        let percents: (user: String, system: String)
        if let total, let system {
            let split = SystemCardLayout.usageSplitPercents(total: total, system: system)
            percents = ("\(split.user)%", "\(split.system)%")
        } else {
            percents = (SystemPaneFormat.placeholder, SystemPaneFormat.placeholder)
        }
        func value(_ text: String) -> DrawnReadoutPiece {
            SystemDrawnText.piece(text, font: MenuPanelStyle.smallValueFont, color: SystemPalette.cpuInk)
        }
        return DrawnReadoutRun(
            groups: [
                [.swatch(color: SystemPalette.cpu, width: 6, height: 6, radius: 1.5), value(percents.user)],
                [.swatch(color: SystemPalette.cpuSecondary, width: 6, height: 6, radius: 1.5),
                 value(percents.system)],
            ],
            innerGap: 2,
            groupGap: 8)
    }
}

// MARK: - GPU 卡

/// GPU 卡 —— 环形利用率 + 60 秒折线 + 显存数值行（版2 不画显存条，下沉到 GPU 详情）
final class SystemGPUCardView: SystemCardView {

    private static let ringDiameter: CGFloat = 40
    private static let ringLineWidth: CGFloat = 5
    private static let sparklineHeight: CGFloat = 28
    /// 环与折线之间的间距（改造前 stack spacing 10）
    private static let ringGap: CGFloat = 10
    /// 环所在行与显存行之间的间距（改造前 stack spacing 4）
    private static let rowGap: CGFloat = 4
    private static let memoryRowHeight: CGFloat = 13
    private static let centerFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    private var fraction: Double = 0
    private var centerText = SystemPaneFormat.placeholder
    private var centerColor: NSColor = SystemPalette.meta
    private var memoryText = SystemPaneFormat.placeholder
    private var memoryColor: NSColor = SystemPalette.meta
    /// 显存行读数（update 时重建，draw 里不再做文本测量）
    private var memoryRun = DrawnReadoutRun()

    /// 60 秒利用率序列（折线）
    var seriesValues: [Double] = [] { didSet { needsDisplay = true } }

    override var contentHeight: CGFloat {
        Self.ringDiameter + Self.rowGap + Self.memoryRowHeight
    }

    /// 刷新环形利用率与显存读数（nil = 空态）
    func update(_ snapshot: GPUSnapshot?) {
        guard let snapshot else {
            fraction = 0
            centerText = SystemPaneFormat.placeholder
            centerColor = SystemPalette.meta
            memoryText = SystemPaneFormat.placeholder
            memoryColor = SystemPalette.meta
            rebuildMemoryRun()
            needsDisplay = true
            return
        }
        let utilization = SystemPaneView.clamp(snapshot.utilization)
        fraction = utilization
        centerText = SystemPaneFormat.percent(utilization)
        centerColor = SystemPalette.gpuInk
        // 统一内存机型取不到显存总量：只给已用量（不显示半条假比例）
        if let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 {
            memoryText = SystemPaneFormat.bytes(used) + " / " + SystemPaneFormat.bytes(total)
        } else if let used = snapshot.memoryUsed {
            memoryText = SystemPaneFormat.bytes(used)
        } else {
            memoryText = SystemPaneFormat.placeholder
        }
        memoryColor = snapshot.memoryUsed == nil ? SystemPalette.meta : SystemPalette.gpuInk
        rebuildMemoryRun()
        needsDisplay = true
    }

    /// 显存行读数：「显存」9pt 三级色 + 已用/总量 10pt 族 ink（update 时重建）
    private func rebuildMemoryRun() {
        memoryRun = DrawnReadoutRun(
            groups: [[
                SystemDrawnText.piece("显存", font: SystemPaneStyle.microFont,
                                      color: SystemPalette.meta),
                SystemDrawnText.piece(memoryText, font: MenuPanelStyle.smallValueFont,
                                      color: memoryColor),
            ]],
            innerGap: 4)
    }

    override var contentAccessibilityText: String {
        "利用率 " + centerText + "，显存 " + memoryText
    }

    override func drawContent(in rect: CGRect) {
        let ringRect = CGRect(x: rect.minX, y: rect.minY,
                              width: Self.ringDiameter, height: Self.ringDiameter)
        DrawnInk.ring(in: ringRect,
                      fraction: fraction,
                      lineWidth: Self.ringLineWidth,
                      color: SystemPalette.gpu,
                      track: SystemPalette.track)
        let centerRun = SystemDrawnText.run(centerText, font: Self.centerFont, color: centerColor)
        centerRun.draw(topIn: CGRect(x: ringRect.midX - centerRun.layoutWidth / 2,
                                     y: ringRect.midY - centerRun.labelHeight / 2,
                                     width: centerRun.layoutWidth,
                                     height: centerRun.labelHeight),
                       alignment: .center)
        let sparkX = rect.minX + Self.ringDiameter + Self.ringGap
        let sparkRect = CGRect(x: sparkX,
                               y: rect.minY + (Self.ringDiameter - Self.sparklineHeight) / 2,
                               width: max(rect.maxX - sparkX, 0),
                               height: Self.sparklineHeight)
        SystemChartDrawing.drawSparkline(values: seriesValues,
                                         in: sparkRect,
                                         lineColor: SystemPalette.gpu,
                                         fixedMaximum: nil,
                                         fillsArea: true,
                                         trackColor: SystemPalette.track)
        let rowRect = CGRect(x: rect.minX,
                             y: rect.maxY - Self.memoryRowHeight,
                             width: rect.width,
                             height: Self.memoryRowHeight)
        memoryRun.draw(at: rowRect.minX, centerY: rowRect.midY)
    }

}

