import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - 鼠标滚轮平滑设置卡

/// 鼠标滚轮平滑设置卡 —— 一张卡五行：开关 / 速度增益 / 持续时间 / 最短步长 / 反向滚动
///
/// 与 `SettingsNotificationEventCard` 同族视觉：同一 `SettingsCardView` + `SettingsRowView`，
/// 行内控件沿用「滑块 140pt + 等宽数值 56pt」这一档（与「截图与贴图」页的 JPEG 质量同款），
/// 不另造设计语言。
///
/// 写偏好即热生效：每个控件写完立刻回调 `onChange`（组合根据此让引擎重读参数），
/// 没有这条回调就是「滑块拖了、手感没变」。
///
/// 主开关关闭时下面四个控件置灰：不是隐藏 —— 用户看得见自己的调参还在，再开回来即恢复。
@MainActor
final class SettingsSmoothScrollCard {

    /// 卡片本体 —— 调用方 `page.addCard(card.card, sectionTitle: "鼠标滚轮")`
    let card = SettingsCardView()

    private let settings: SmoothScrollSettings
    /// 引擎当前状态说明（主开关行的副标题）
    private let stateText: () -> String
    /// 写偏好之后的回调（组合根让引擎热生效）
    private let onChange: () -> Void

    // MARK: - 控件

    private let masterRow = SettingsRowView(title: "鼠标滚轮平滑",
                                            subtitle: "仅对物理滚轮生效：触控板与惯性滚动原样放行")
    private let masterSwitch = NSSwitch()
    private let gainRow = SettingsRowView(title: "速度增益",
                                          subtitle: "越大滚得越快；1.00 倍即原始速度")
    private let gainSlider = NSSlider()
    private let gainValue = SettingsSmoothScrollCard.makeValueLabel()
    private let durationRow = SettingsRowView(title: "持续时间",
                                              subtitle: "一次滚轮拆完的最长跨度；越大越绵")
    private let durationSlider = NSSlider()
    private let durationValue = SettingsSmoothScrollCard.makeValueLabel()
    private let stepRow = SettingsRowView(title: "最短步长",
                                          subtitle: "单次回投至少走这么多；越小越细、事件越多")
    private let stepSlider = NSSlider()
    private let stepValue = SettingsSmoothScrollCard.makeValueLabel()
    private let reverseRow = SettingsRowView(title: "反向滚动",
                                             subtitle: "上下互换，与「自然滚动」方向不一致时用")
    private let reverseSwitch = NSSwitch()

    /// 滑块统一宽度（与截图页 JPEG 质量同档）
    private static let sliderWidth: CGFloat = 140
    /// 数值标签统一宽度（等宽数字不跳动）
    private static let valueWidth: CGFloat = 56

    // MARK: - 初始化

    init(settings: SmoothScrollSettings,
         stateText: @escaping () -> String,
         onChange: @escaping () -> Void) {
        self.settings = settings
        self.stateText = stateText
        self.onChange = onChange
        buildRows()
        // 构建完立刻按偏好灌一次：离屏快照与首次进页都不保证走到 refresh
        refresh()
    }

    // MARK: - 构建

    private func buildRows() {
        masterSwitch.target = self
        masterSwitch.action = #selector(masterChanged)
        masterSwitch.setAccessibilityLabel("鼠标滚轮平滑")
        masterRow.trailingStack.addArrangedSubview(masterSwitch)

        configureSlider(gainSlider,
                        range: SmoothScrollParameters.speedGainRange,
                        accessibility: "速度增益",
                        action: #selector(gainChanged))
        gainRow.trailingStack.addArrangedSubview(makeSliderStack(gainSlider, gainValue))

        configureSlider(durationSlider,
                        range: SmoothScrollParameters.durationRange,
                        accessibility: "持续时间",
                        action: #selector(durationChanged))
        durationRow.trailingStack.addArrangedSubview(makeSliderStack(durationSlider, durationValue))

        configureSlider(stepSlider,
                        range: SmoothScrollParameters.minStepRange,
                        accessibility: "最短步长",
                        action: #selector(minStepChanged))
        stepRow.trailingStack.addArrangedSubview(makeSliderStack(stepSlider, stepValue))

        reverseSwitch.target = self
        reverseSwitch.action = #selector(reverseChanged)
        reverseSwitch.setAccessibilityLabel("反向滚动")
        reverseRow.trailingStack.addArrangedSubview(reverseSwitch)

        card.addRow(masterRow)
        card.addRow(gainRow)
        card.addRow(durationRow)
        card.addRow(stepRow)
        card.addRow(reverseRow)
    }

    private func configureSlider(_ slider: NSSlider,
                                 range: ClosedRange<Double>,
                                 accessibility: String,
                                 action: Selector) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.isContinuous = true
        slider.target = self
        slider.action = action
        slider.setAccessibilityLabel(accessibility)
        slider.widthAnchor.constraint(equalToConstant: Self.sliderWidth).isActive = true
    }

    /// 滑块 + 数值：横排 8pt 间距（与截图页 JPEG 质量同款）
    private func makeSliderStack(_ slider: NSSlider, _ value: NSTextField) -> NSStackView {
        let stack = NSStackView(views: [slider, value])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private static func makeValueLabel() -> NSTextField {
        let label = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                        color: SettingsTheme.textSecondary)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: valueWidth).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    // MARK: - 刷新

    /// 按偏好灌控件（切页 / 重新显示 / 状态变化后调用）
    func refresh() {
        let parameters = settings.parameters
        masterSwitch.state = parameters.enabled ? .on : .off
        masterRow.update(subtitle: stateText())
        gainSlider.doubleValue = parameters.speedGain
        durationSlider.doubleValue = parameters.duration
        stepSlider.doubleValue = parameters.minStep
        reverseSwitch.state = parameters.reverseDirection ? .on : .off
        updateValueLabels(parameters)
        updateControlAvailability(parameters.enabled)
    }

    /// 主开关关闭时四个从属控件置灰（看得见、点不动、不再写偏好）
    private func updateControlAvailability(_ enabled: Bool) {
        gainSlider.isEnabled = enabled
        durationSlider.isEnabled = enabled
        stepSlider.isEnabled = enabled
        reverseSwitch.isEnabled = enabled
    }

    private func updateValueLabels(_ parameters: SmoothScrollParameters) {
        gainValue.stringValue = String(format: "%.2f×", parameters.speedGain)
        durationValue.stringValue = String(format: "%.0f ms", parameters.duration * 1000)
        stepValue.stringValue = String(format: "%.2f 行", parameters.minStep)
    }

#if DEBUG
    /// 取证：控件态 / 偏好真值 / 从属控件可用性并排落盘
    ///
    /// 离屏快照看不出开关的勾选态与滑块的置灰态（窗口不 key 时系统控件一律灰），
    /// 所以「界面上是不是真的跟着偏好走」只能靠这行文本对账。
    func debugLogStates(_ tag: String) {
        let parameters = settings.parameters
        let line = "[\(tag)] 开关=\(masterSwitch.state == .on ? "on" : "off")/\(parameters.enabled ? "on" : "off") "
            + "增益=\(Self.format(gainSlider.doubleValue))/\(Self.format(parameters.speedGain)) "
            + "时长=\(Self.format(durationSlider.doubleValue))/\(Self.format(parameters.duration)) "
            + "步长=\(Self.format(stepSlider.doubleValue))/\(Self.format(parameters.minStep)) "
            + "反向=\(reverseSwitch.state == .on)/\(parameters.reverseDirection) "
            + "从属可用=\(gainSlider.isEnabled)/\(stepSlider.isEnabled) 状态行=\(stateText())"
        SnapshotEvidenceLine.write(line, tag: tag, fileName: "settings-smoothing-states.txt")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
#endif

    // MARK: - 动作（写偏好 → 刷新显示 → 通知引擎）

    @objc private func masterChanged() {
        settings.setEnabled(masterSwitch.state == .on)
        // 先让引擎按新开关生效，再刷状态行（否则显示的还是上一次的状态）
        onChange()
        refresh()
    }

    @objc private func gainChanged() {
        settings.setSpeedGain(gainSlider.doubleValue)
        applyCurrentParameters()
    }

    @objc private func durationChanged() {
        settings.setDuration(durationSlider.doubleValue)
        applyCurrentParameters()
    }

    @objc private func minStepChanged() {
        settings.setMinStep(stepSlider.doubleValue)
        applyCurrentParameters()
    }

    @objc private func reverseChanged() {
        settings.setReverseDirection(reverseSwitch.state == .on)
        onChange()
    }

    /// 滑块：写偏好后重新读回归一化值（落盘值可能与滑块值不同）并刷新数值标签
    private func applyCurrentParameters() {
        let parameters = settings.parameters
        gainSlider.doubleValue = parameters.speedGain
        durationSlider.doubleValue = parameters.duration
        stepSlider.doubleValue = parameters.minStep
        updateValueLabels(parameters)
        onChange()
    }
}
