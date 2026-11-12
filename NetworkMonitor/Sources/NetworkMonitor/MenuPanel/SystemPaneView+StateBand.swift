import AppKit
import NetworkMonitorCore

// MARK: - 底部状态带

/// 底部状态带 — SoC 温度 · 电池环 + 电量 · Wi-Fi 三段，一行横跨面板底部
///
/// 温度卡下线后的替代形态：只占状态带那一行（`PaneCardStyle.stateBandHeight`），不再是独立卡片。
/// 外壳（底 / 高度 / 内边距 / 圆角）全部走 `PaneBandChrome`：此前这里自己画
/// `SystemPalette.bandBackground`（0xF0F0F4）+ 6pt 圆角 + 写死 7pt 内边距与 20pt 高，
/// 与额度 / Token 页的 0xEEEFF2 / bandRadius 是第三份实现，切页时页脚底色与字号都能看出差别。
///
/// **第四段「估功耗」已从正文移到 toolTip**（`updatePower` 的 API 不变，读数照旧可取）：
/// 字号统一到 10pt 键 / 10.5pt 值后，四段最宽组合实测 307pt（电池 100% · 温度 105° ·
/// RSSI −100 · 功耗 48.20 W；按 `NSTextField.fittingSize` 量），状态带内宽只有 282pt
/// （面板内容 296 − 2×`bandPaddingX`）。砍掉功耗段后三段最宽组合 228pt，余量 54pt，
/// 三段按 `bandGroupSpacing` 排布后不再挤压。
/// 口径全部写在 toolTip：健康度不可得（只给循环次数）、功耗为估算值、GPU 温度与风扇不可得。
final class SystemStateBandView: NSView {

    private let tempCaption: NSTextField
    private let tempValue: NSTextField
    private let batteryRing: SystemBatteryRingView
    private let batteryValue: NSTextField
    private let batteryNote: NSTextField
    // MARK: Wi-Fi 段
    // 只放 RSSI 与档位色点：信道 / 速率在状态带内宽里放不下（在网络页链路条上）。
    private let wifiCaption: NSTextField
    private let wifiValue: NSTextField
    private let wifiDot: WiFiSignalDotView

    /// 温度段与电池段小组（`setShowsTemperature` 按组显隐，避免留半截标签）
    private let tempGroup: NSStackView
    private let batteryGroup: NSStackView

    /// 功耗读数（正文第四段已移除，见类型注释的取舍）—— 与 toolTip 合并展示
    private(set) var powerText: String = SystemPaneFormat.placeholder

    /// 调用方写进来的口径说明（`SystemPaneTip.band(...)`），与功耗读数合并后再交给 AppKit
    private var baseToolTip: String?

    init() {
        tempCaption = MenuPanelLabel.text("SoC", font: PaneCardStyle.metaFont,
                                          color: SystemPalette.meta)
        tempValue = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: PaneCardStyle.rowValueStrongFont,
                                        color: SystemPalette.temperatureInk)
        batteryRing = SystemBatteryRingView()
        batteryValue = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                           font: PaneCardStyle.rowValueStrongFont,
                                           color: SystemPalette.batteryInk)
        // 「充 / AC」是电量之外的补充标记：与键同一档字号、走三级色，不加粗也不放大
        batteryNote = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                         color: SystemPalette.meta)
        wifiCaption = MenuPanelLabel.text("Wi-Fi", font: PaneCardStyle.metaFont,
                                         color: SystemPalette.meta)
        wifiValue = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                       font: PaneCardStyle.rowValueStrongFont,
                                       color: SystemPalette.wifiInk)
        wifiDot = WiFiSignalDotView()
        tempGroup = Self.group([tempCaption, tempValue])
        batteryGroup = Self.group([batteryRing, batteryValue, batteryNote])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [tempGroup, batteryGroup,
                                          Self.group([wifiCaption, wifiValue, wifiDot]),
                                          MenuPanelLabel.spacer()])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = PaneCardStyle.bandGroupSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        // 底 / 高度 / 内边距 / 圆角与其它页同一个壳（高度 = stateBandHeight，内边距 = bandPaddingX）
        PaneBandChrome.constrain(content, in: self)
        for label in [tempValue, batteryValue, wifiValue] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("系统状态带")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        PaneBandChrome.draw(in: bounds)
        super.draw(dirtyRect)
    }

    // MARK: toolTip（口径说明 + 功耗读数）

    /// 状态带 toolTip —— 口径说明由 `SystemPaneView+Metrics` 写入，功耗读数由本视图补在末尾
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
        guard let celsius, celsius.isFinite else {
            tempValue.stringValue = SystemPaneFormat.placeholder
            tempValue.textColor = SystemPalette.meta
            return
        }
        tempValue.stringValue = SystemPaneFormat.temperatureNumber(celsius) + "°"
        tempValue.textColor = celsius > SystemPaneFormat.hotThreshold
            ? SystemPaneStyle.temperatureHot : SystemPalette.temperatureInk
    }

    /// 电池段 — 环 + 电量 + 状态小字（充 / AC）；循环次数进 toolTip（健康度不可得）
    func updateBattery(_ snapshot: BatterySnapshot?) {
        guard let snapshot else {
            batteryRing.fraction = 0
            batteryRing.tone = .unavailable
            batteryValue.stringValue = SystemPaneFormat.placeholder
            batteryValue.textColor = SystemPalette.meta
            batteryNote.stringValue = ""
            return
        }
        // 状态小字独立于电量：电量读不到不代表电源状态读不到，
        // 「— AC」与「—」是两种不同的事实，不能因为缺电量就把供电状态一起抹掉
        if snapshot.isCharging == true {
            batteryNote.stringValue = "充"
        } else if snapshot.isOnAC == true {
            batteryNote.stringValue = "AC"
        } else {
            batteryNote.stringValue = ""
        }
        guard let percentage = snapshot.percentage, percentage.isFinite else {
            batteryRing.fraction = 0
            batteryRing.tone = .unavailable
            batteryValue.stringValue = SystemPaneFormat.placeholder
            batteryValue.textColor = SystemPalette.meta
            return
        }
        let ratio = SystemPaneFormat.unitFraction(percentage)
        batteryRing.fraction = ratio
        batteryRing.tone = ratio < 0.10 ? .critical : (ratio < 0.20 ? .warning : .normal)
        batteryValue.stringValue = SystemPaneFormat.percent(percentage)
        batteryValue.textColor = SystemPalette.batteryInk
    }

    /// GPU 功耗段（估算值；nil 显示「—」）
    ///
    /// 正文不再占第四段：读数写进 toolTip，并同步到无障碍值，读屏仍能听到功耗。
    func updatePower(_ watts: Double?) {
        guard let watts, watts.isFinite else {
            powerText = SystemPaneFormat.placeholder
            refreshPowerSurface()
            return
        }
        powerText = String(format: "%.2f W", max(0, watts))
        refreshPowerSurface()
    }

    /// 功耗读数落盘到两处可见面（toolTip / 无障碍值）—— 正文已无第四段可写
    private func refreshPowerSurface() {
        super.toolTip = mergedToolTip()
        setAccessibilityValue("估功耗 " + powerText)
    }

    /// Wi-Fi 段 — 只放 RSSI 与档位色点
    ///
    /// 读不到时段内显示「—」且圆点转灰：整段保留而不是隐藏，
    /// 避免温度 / 电池的位置随 Wi-Fi 有无左右横跳；也不写 0 dBm 冒充读数。
    func updateWiFi(_ snapshot: WiFiLinkSnapshot?) {
        let available = WiFiLinkFormatting.isAvailable(snapshot)
        wifiValue.stringValue = WiFiLinkFormatting.rssiText(snapshot)
        wifiValue.textColor = available ? SystemPalette.wifiInk : SystemPalette.meta
        wifiDot.quality = available ? WiFiLinkFormatting.quality(snapshot) : .unknown
        setAccessibilityLabel("系统状态带")
    }

    /// 温度是否显示（设置页 PanelItem.thermal 开关的新语义）
    func setShowsTemperature(_ shows: Bool) {
        tempGroup.isHidden = !shows
    }

    /// 三段「标签 + 数值」横向小组（组内间距 = bandInnerSpacing）
    private static func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = PaneCardStyle.bandInnerSpacing
        return stack
    }
}

// MARK: - 电池环

/// 14pt 电池环 — 弧长按电量百分比
///
/// 颜色用**纯系统绿**，绝不与强调色混合：v3 用 success + accent 40% 在 oklab 插值后
/// hue 落到 178°（青）被打回。低电量转琥珀 / 红，与状态语义一致。
final class SystemBatteryRingView: NSView {

    /// 档位（决定环色）
    enum Tone {
        case normal
        case warning
        case critical
        case unavailable
    }

    /// 电量比例 0...1
    var fraction: Double = 0 {
        didSet {
            guard fraction != oldValue else { return }
            needsDisplay = true
        }
    }

    var tone: Tone = .unavailable {
        didSet {
            guard tone != oldValue else { return }
            needsDisplay = true
        }
    }

    private static let lineWidth: CGFloat = 2.6

    init(size: CGFloat = 14) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        setAccessibilityRole(.image)
        setAccessibilityLabel("电池电量环")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = max(1, (min(bounds.width, bounds.height) - Self.lineWidth) / 2)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = Self.lineWidth
        SystemPalette.track.setStroke()
        track.stroke()

        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard value > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(value), clockwise: true)
        arc.lineWidth = Self.lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private var color: NSColor {
        switch tone {
        case .normal: return SystemPaneStyle.batteryRing
        case .warning: return SystemPaneStyle.batteryWarn
        case .critical: return SystemPaneStyle.batteryCritical
        case .unavailable: return SystemPalette.track
        }
    }
}
