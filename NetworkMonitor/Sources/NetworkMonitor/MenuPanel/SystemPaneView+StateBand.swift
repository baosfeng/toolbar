import AppKit
import NetworkMonitorCore

// MARK: - 底部状态带

/// 底部状态带 — SoC 温度 · 电池环 + 电量 · 估功耗，一行三段横跨面板底部
///
/// 温度卡下线后的替代形态：只占约 20pt 一行，不再是独立卡片。
/// 口径全部写在 toolTip：健康度不可得（只给循环次数）、功耗为估算值、GPU 温度与风扇不可得。
final class SystemStateBandView: NSView {

    private let tempCaption: NSTextField
    private let tempValue: NSTextField
    private let batteryRing: SystemBatteryRingView
    private let batteryValue: NSTextField
    private let batteryNote: NSTextField
    private let powerCaption: NSTextField
    private let powerValue: NSTextField

    init() {
        tempCaption = MenuPanelLabel.text("SoC", font: SystemPaneStyle.microFont,
                                          color: MenuPanelStyle.tertiaryText)
        tempValue = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: MenuPanelStyle.smallValueFont,
                                        color: MenuPanelStyle.secondaryText)
        batteryRing = SystemBatteryRingView()
        batteryValue = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                           font: MenuPanelStyle.smallValueFont,
                                           color: MenuPanelStyle.secondaryText)
        batteryNote = MenuPanelLabel.text("", font: SystemPaneStyle.tinyFont,
                                          color: MenuPanelStyle.tertiaryText)
        // 「估」紧跟「功耗」：GPU 功耗是累加器估算，不是功耗计读数，不能只写数字
        powerCaption = MenuPanelLabel.text("估功耗", font: SystemPaneStyle.microFont,
                                           color: MenuPanelStyle.tertiaryText)
        powerValue = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                         font: MenuPanelStyle.smallValueFont,
                                         color: MenuPanelStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let tempGroup = Self.group([tempCaption, tempValue])
        let batteryGroup = Self.group([batteryRing, batteryValue, batteryNote])
        let powerGroup = Self.group([powerCaption, powerValue])
        let stack = NSStackView(views: [tempGroup, batteryGroup, MenuPanelLabel.spacer(), powerGroup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20),
        ])
        for label in [tempValue, batteryValue, powerValue] {
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("系统状态带")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        MenuPanelStyle.subtleFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }

    // MARK: 更新

    /// 温度段（nil 显示「—」；>85°C 转警示色）
    func updateTemperature(_ celsius: Double?) {
        guard let celsius, celsius.isFinite else {
            tempValue.stringValue = SystemPaneFormat.placeholder
            tempValue.textColor = MenuPanelStyle.tertiaryText
            return
        }
        tempValue.stringValue = SystemPaneFormat.temperatureNumber(celsius) + "°"
        tempValue.textColor = celsius > SystemPaneFormat.hotThreshold
            ? .systemRed : MenuPanelStyle.secondaryText
    }

    /// 电池段 — 环 + 电量 + 状态小字（充 / AC）；循环次数进 toolTip（健康度不可得）
    func updateBattery(_ snapshot: BatterySnapshot?) {
        guard let snapshot else {
            batteryRing.fraction = 0
            batteryRing.tone = .unavailable
            batteryValue.stringValue = SystemPaneFormat.placeholder
            batteryValue.textColor = MenuPanelStyle.tertiaryText
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
            batteryValue.textColor = MenuPanelStyle.tertiaryText
            return
        }
        let ratio = SystemPaneFormat.unitFraction(percentage)
        batteryRing.fraction = ratio
        batteryRing.tone = ratio < 0.10 ? .critical : (ratio < 0.20 ? .warning : .normal)
        batteryValue.stringValue = SystemPaneFormat.percent(percentage)
        batteryValue.textColor = MenuPanelStyle.secondaryText
    }

    /// GPU 功耗段（估算值；nil 显示「—」）
    func updatePower(_ watts: Double?) {
        guard let watts, watts.isFinite else {
            powerValue.stringValue = SystemPaneFormat.placeholder
            powerValue.textColor = MenuPanelStyle.tertiaryText
            return
        }
        powerValue.stringValue = String(format: "%.2f W", max(0, watts))
        powerValue.textColor = MenuPanelStyle.secondaryText
    }

    /// 温度是否显示（设置页 PanelItem.thermal 开关的新语义）
    func setShowsTemperature(_ shows: Bool) {
        tempCaption.isHidden = !shows
        tempValue.isHidden = !shows
    }

    /// 三段「标签 + 数值」横向小组
    private static func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
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
        MenuPanelStyle.trackColor.setStroke()
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
        case .unavailable: return MenuPanelStyle.dynamicLabel(alpha: 0.24)
        }
    }
}
