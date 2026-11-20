import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - 底部状态带

/// 底部状态带 —— SoC 温度 · 电池环 + 电量 · Wi-Fi 三段，一行横跨面板底部
///
/// 温度卡下线后的替代形态：只占状态带那一行（PaneCardStyle.stateBandHeight），不再是独立卡片。
/// 外壳（底 / 高度 / 内边距 / 圆角）全部走 PaneBandChrome：此前这里自己画
/// SystemPalette.bandBackground + 6pt 圆角 + 写死 7pt 内边距与 20pt 高，
/// 与额度 / Token 页的 bandFill / bandRadius 是第三份实现。
///
/// **整条一个视图**：三段读数由 DrawnReadoutRun 一次画完（改造前这里 19 个子视图：
/// 3 个 NSStackView 组 + 6 个 NSTextField + 电池环 + 档位点 + 占位）。
///
/// **第四段「估功耗」已从正文移到 toolTip**（updatePower 的 API 不变，读数照旧可取）：
/// 字号统一到 10pt 键 / 10.5pt 值后，四段最宽组合实测 307pt（电池 100% · 温度 105° ·
/// RSSI −100 · 功耗 48.20 W），状态带内宽只有 282pt（面板内容 296 − 2×bandPaddingX）。
/// 砍掉功耗段后三段最宽组合 228pt，余量 54pt，三段按 bandGroupSpacing 排布后不再挤压。
final class SystemStateBandView: NSView {

    // MARK: 数据

    private var temperature: Double?
    private var battery: BatterySnapshot?
    private var wifi: WiFiLinkSnapshot?
    private var showsTemperature = true

    /// 功耗读数（正文第四段已移除，见类型注释的取舍）—— 与 toolTip 合并展示
    private(set) var powerText: String = SystemPaneFormat.placeholder

    /// 调用方写进来的口径说明（SystemPaneTip.band(...)），与功耗读数合并后再交给 AppKit
    private var baseToolTip: String?

    // MARK: 字号（与 PaneBandChrome.makeItemView 同一张表）

    private static let captionFont = PaneCardStyle.metaFont
    private static let valueFont = PaneCardStyle.rowValueStrongFont

    // MARK: 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: PaneBandChrome.height).isActive = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("系统状态带")
        rebuildReadout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 与原生标签同一套字形渲染（字体平滑参与抗锯齿）
        NSGraphicsContext.current?.cgContext.setShouldSubpixelPositionFonts(false)
        NSGraphicsContext.current?.cgContext.setAllowsFontSubpixelPositioning(false)
        PaneBandChrome.draw(in: bounds)
        readoutRun.draw(at: PaneCardStyle.bandPaddingX, centerY: bounds.midY)
        super.draw(dirtyRect)
    }

    // MARK: 读数条（三段：温度 / 电池 / Wi-Fi）

    /// 整条读数（在 update 里重建，draw 里不再做文本测量）
    private var readoutRun = DrawnReadoutRun()

    /// 重建读数：组间 8pt、组内 3pt（与 PaneCardStyle 的 band 间距同源）
    private func rebuildReadout() {
        var groups: [[DrawnReadoutPiece]] = []
        if showsTemperature { groups.append(temperatureGroup) }
        groups.append(batteryGroup)
        groups.append(wifiGroup)
        readoutRun = DrawnReadoutRun(groups: groups,
                                     innerGap: PaneCardStyle.bandInnerSpacing,
                                     groupGap: PaneCardStyle.bandGroupSpacing)
    }

    /// 「SoC 温度」（>85°C 转警示色）
    private var temperatureGroup: [DrawnReadoutPiece] {
        let hot = (temperature ?? 0) > SystemPaneFormat.hotThreshold
        let text: String
        let color: NSColor
        if let temperature, temperature.isFinite {
            text = SystemPaneFormat.temperatureNumber(temperature) + "°"
            color = hot ? SystemPaneStyle.temperatureHot : SystemPalette.temperatureInk
        } else {
            text = SystemPaneFormat.placeholder
            color = SystemPalette.meta
        }
        return [
            caption("SoC"),
            value(text, color: color),
        ]
    }

    /// 「电量环 + 电量 + 充 / AC」
    private var batteryGroup: [DrawnReadoutPiece] {
        let ratio = battery.flatMap { $0.percentage }.map { SystemPaneFormat.unitFraction($0) } ?? 0
        let tone: BatteryTone
        if battery?.percentage == nil {
            tone = .unavailable
        } else {
            tone = ratio < 0.10 ? .critical : (ratio < 0.20 ? .warning : .normal)
        }
        let valueText = battery.flatMap { $0.percentage }.map { SystemPaneFormat.percent($0) }
            ?? SystemPaneFormat.placeholder
        let valueColor = battery?.percentage == nil ? SystemPalette.meta : SystemPalette.batteryInk
        // 状态小字独立于电量：电量读不到不代表电源状态读不到
        let note = battery?.isCharging == true ? "充" : (battery?.isOnAC == true ? "AC" : "")
        var pieces: [DrawnReadoutPiece] = [
            .ring(fraction: ratio,
                  diameter: Self.batteryRingSize,
                  lineWidth: Self.batteryRingLineWidth,
                  color: tone.color,
                  track: SystemPalette.track),
            value(valueText, color: valueColor),
        ]
        if !note.isEmpty {
            pieces.append(caption(note))
        }
        return pieces
    }

    /// 「Wi-Fi + RSSI + 档位圆点」
    private var wifiGroup: [DrawnReadoutPiece] {
        let available = wifi.map { WiFiLinkFormatting.isAvailable($0) } ?? false
        let rssi = WiFiLinkFormatting.rssiText(wifi)
        let quality = available ? WiFiLinkFormatting.quality(wifi) : .unknown
        return [
            caption("Wi-Fi"),
            value(rssi, color: available ? SystemPalette.wifiInk : SystemPalette.meta),
            .dot(color: WiFiLinkStyle.dotColor(for: quality),
                 size: WiFiLinkStyle.dotDiameter,
                 ringColor: MenuPanelStyle.trackColor),
        ]
    }

    /// 一段次级色说明文字
    private func caption(_ text: String) -> DrawnReadoutPiece {
        SystemDrawnText.piece(text, font: Self.captionFont, color: SystemPalette.meta)
    }

    /// 一段读数文字（值）
    private func value(_ text: String, color: NSColor) -> DrawnReadoutPiece {
        SystemDrawnText.piece(text, font: Self.valueFont, color: color)
    }

    // MARK: 电池环规格

    private static let batteryRingSize: CGFloat = 14
    private static let batteryRingLineWidth: CGFloat = 2.6

    /// 电池档位（决定环色）：正常 / 警告 / 极低 / 不可得
    @MainActor
    private enum BatteryTone {
        case normal
        case warning
        case critical
        case unavailable

        var color: NSColor {
            switch self {
            case .normal: return SystemPaneStyle.batteryRing
            case .warning: return SystemPaneStyle.batteryWarn
            case .critical: return SystemPaneStyle.batteryCritical
            case .unavailable: return SystemPalette.track
            }
        }
    }

    // MARK: toolTip（口径说明 + 功耗读数）

    /// 状态带 toolTip —— 口径说明由 SystemPaneView+Metrics 写入，功耗读数由本视图补在末尾
    ///
    /// 重写而不是在各 update 里拼字符串：口径文案的写入点在另一个文件、时序在本视图之后，
    /// 只有把「基底文案」与「功耗读数」两段分开存，谁后写都不会把对方覆盖掉。
    override var toolTip: String? {
        get { baseToolTip }
        set {
            baseToolTip = newValue
            super.toolTip = mergedToolTip()
        }
    }

    /// 合并后的说明：基底 + 功耗读数（读数缺失时同样写出「—」，不悄悄省略）
    private func mergedToolTip() -> String {
        let power = "「估功耗」\(powerText)（GPU 功耗估算值；状态带正文内宽放不下第四段，读数挂在此处）"
        guard let base = baseToolTip, !base.isEmpty else { return power }
        return base + "；" + power
    }

    // MARK: 更新

    /// 温度段（nil 显示「—」；>85°C 转警示色）
    func updateTemperature(_ celsius: Double?) {
        temperature = celsius
        rebuildReadout()
        needsDisplay = true
    }

    /// 电池段 — 环 + 电量 + 状态小字（充 / AC）；循环次数进 toolTip（健康度不可得）
    func updateBattery(_ snapshot: BatterySnapshot?) {
        battery = snapshot
        rebuildReadout()
        needsDisplay = true
    }

    /// GPU 功耗段（估算值；nil 显示「—」）
    ///
    /// 正文不再占第四段：读数写进 toolTip，并同步到无障碍值，读屏仍能听到功耗。
    func updatePower(_ watts: Double?) {
        if let watts, watts.isFinite {
            powerText = String(format: "%.2f W", max(0, watts))
        } else {
            powerText = SystemPaneFormat.placeholder
        }
        super.toolTip = mergedToolTip()
        setAccessibilityValue("估功耗 " + powerText)
    }

    /// Wi-Fi 段 — 只放 RSSI 与档位色点
    ///
    /// 读不到时段内显示「—」且圆点转灰：整段保留而不是隐藏，
    /// 避免温度 / 电池的位置随 Wi-Fi 有无左右横跳；也不写 0 dBm 冒充读数。
    func updateWiFi(_ snapshot: WiFiLinkSnapshot?) {
        wifi = snapshot
        rebuildReadout()
        needsDisplay = true
    }

    /// 温度是否显示（设置页 PanelItem.thermal 开关的新语义）
    func setShowsTemperature(_ shows: Bool) {
        guard showsTemperature != shows else { return }
        showsTemperature = shows
        rebuildReadout()
        needsDisplay = true
    }
}
