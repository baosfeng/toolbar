import AppKit
import NetworkMonitorCore

// MARK: - Wi-Fi 链路条（网络页）

/// Wi-Fi 链路条 — 20pt 一行，与系统页底部状态带同一视觉规格
///
/// 形态：`Wi-Fi  −65 dBm  ch36 5G  103 Mbps  ·`（末尾圆点表档位）
/// 规则：
/// - 界面只出现数值 / 单位 / ≤4 字标签；口径全部进 `toolTip`（由 Core 拼装）；
/// - 档位颜色只用既有语义色（见 `WiFiLinkStyle`），不新造紫 / 青，不做混色；
/// - 读不到时**整条保留**并全部显示「—」：整条隐藏会让下方区块跳动 30pt，
///   且「Wi-Fi 不可得」与「这台机器没有 Wi-Fi 这件事」是两种事实，前者要能看见；
/// - 只在系统指标 5 秒慢节拍更新时刷新，不做逐帧动画。
final class WiFiLinkBarView: NSView {

    private let titleLabel = MenuPanelLabel.text("Wi-Fi", font: SystemPaneStyle.microFont,
                                                 color: MenuPanelStyle.tertiaryText)
    private let rssiValue = MenuPanelLabel.text(WiFiLinkFormatting.placeholder,
                                                font: WiFiLinkStyle.valueFont,
                                                color: MenuPanelStyle.secondaryText)
    private let rssiUnit = MenuPanelLabel.text("dBm", font: SystemPaneStyle.microFont,
                                               color: MenuPanelStyle.tertiaryText)
    private let channelValue = MenuPanelLabel.text(WiFiLinkFormatting.placeholder,
                                                   font: WiFiLinkStyle.valueFont,
                                                   color: MenuPanelStyle.secondaryText)
    private let rateValue = MenuPanelLabel.text(WiFiLinkFormatting.placeholder,
                                                font: WiFiLinkStyle.valueFont,
                                                color: MenuPanelStyle.secondaryText)
    private let rateUnit = MenuPanelLabel.text("Mbps", font: SystemPaneStyle.microFont,
                                               color: MenuPanelStyle.tertiaryText)
    private let qualityDot = WiFiSignalDotView()

    /// 最近一次渲染的内容签名 — 5 秒节拍下数据多数帧不变，跳过无意义的重设
    private var signature = ""

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let rssiGroup = Self.group([titleLabel, rssiValue, rssiUnit])
        let channelGroup = Self.group([channelValue])
        let rateGroup = Self.group([rateValue, rateUnit])

        let stack = NSStackView(views: [rssiGroup, channelGroup, rateGroup,
                                        MenuPanelLabel.spacer(), qualityDot])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        // 组间距统一到状态带档（原 9pt 是这一条独有的取值）
        stack.spacing = PaneCardStyle.bandGroupSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // 与页脚状态带同一个壳（底 / 高度 / 内边距 / 圆角全部走 PaneBandChrome）
        PaneBandChrome.constrain(stack, in: self)
        // 数值列必须收敛到自身固有宽度：这是「先算宽度再排版」的落地方式，
        // 不靠 lineBreakMode 截断糊过去（截断后「103 Mbps」会变成「103 M…」）
        for label in [rssiValue, channelValue, rateValue] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for label in [titleLabel, rssiUnit, rateUnit] {
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Wi-Fi 链路")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        PaneBandChrome.draw(in: bounds)
        super.draw(dirtyRect)
    }

    // MARK: - 更新

    /// 刷新链路条 — nil / 脏数据统一走「整条 —」形态，绝不显示 0 dBm 或「极佳」
    func update(_ snapshot: WiFiLinkSnapshot?) {
        let available = WiFiLinkFormatting.isAvailable(snapshot)
        let rssi = WiFiLinkFormatting.rssiText(snapshot)
        let channel = WiFiLinkFormatting.channelText(snapshot)
        let rate = WiFiLinkFormatting.rateText(snapshot)
        let quality = WiFiLinkFormatting.quality(snapshot)

        let newSignature = "\(available)|\(rssi)|\(channel)|\(rate)|\(quality.rawValue)"
        guard newSignature != signature else { return }
        signature = newSignature

        rssiValue.stringValue = rssi
        channelValue.stringValue = channel
        rateValue.stringValue = rate
        // 单位跟着数值一起降级：只留「—」时不出现「dBm」「Mbps」这种没有主语的后缀
        rssiUnit.isHidden = !available
        rateUnit.isHidden = !available
        // 不可用时整个值列降到三级文字色（与系统页各卡空态同一口径）
        let valueColor = available ? MenuPanelStyle.secondaryText : MenuPanelStyle.tertiaryText
        for label in [rssiValue, channelValue, rateValue] {
            label.textColor = valueColor
        }
        qualityDot.quality = available ? quality : .unknown

        let tip = WiFiLinkFormatting.toolTip(snapshot)
        toolTip = tip
        setAccessibilityLabel(WiFiLinkFormatting.accessibilityLabel(snapshot))
    }

    /// 「标签 + 数值」横向小组
    private static func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        return stack
    }
}

// MARK: - 信号档位圆点

/// 7pt 信号档位圆点 — 绿 / 蓝 / 黄 / 红四档，未知为轨道灰
///
/// 颜色只从 `WiFiLinkStyle` 取（全部为既有语义色），不在此处写颜色字面量。
final class WiFiSignalDotView: NSView {

    /// 档位（未知 = 灰，表达「不可判定」而非「很差」）
    var quality: WiFiSignalQuality = .unknown {
        didSet {
            guard quality != oldValue else { return }
            needsDisplay = true
            // 标签必须随档位更新：只设一次常量时，导航到圆点永远听不到强弱
            setAccessibilityLabel("Wi-Fi 信号档位：" + WiFiLinkFormatting.qualityText(quality))
        }
    }

    init(diameter: CGFloat = 7) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        setAccessibilityRole(.image)
        // 档位原本只靠颜色表达（色弱不可辨），读屏标签是常量，导航到圆点听不到强弱
        setAccessibilityLabel("Wi-Fi 信号档位：" + WiFiLinkFormatting.qualityText(quality))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        WiFiLinkStyle.dotColor(for: quality).setFill()
        circle.fill()
        // 浅色底色上 systemGreen / systemYellow 与背景对比不足 3:1：
        // 用一圈轨道色内边把色块从背景里「框」出来，而不是把颜色调深（调深就是混色）
        MenuPanelStyle.trackColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }
}
