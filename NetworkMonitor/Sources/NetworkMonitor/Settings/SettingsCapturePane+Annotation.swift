import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI
import NetworkMonitorFeatureSnip

// MARK: - 截图设置页：标注卡片

/// 「标注」卡片（默认颜色 / 线宽 / 线型 / 字号）的组装、回灌与动作
///
/// 从 SettingsCapturePane 主文件拆出：主文件同时装着贴图、保存、识别、快捷键五张卡，
/// 加上本轮新增的字号与虚线两行后逼到单文件体积门禁。这里只做「标注这支笔的默认值」。
///
/// 三条偏好键的消费方在覆盖层（`SnipAnnotationStyleResolver` → `SnipOverlayView.currentStyle`），
/// 设置页只负责写；用户改完下一次截图即生效。
extension SettingsCapturePane {

    // MARK: - 组装

    func buildAnnotationSection() {
        buildColorButtons()
        let swatches = NSStackView()
        swatches.orientation = .horizontal
        swatches.alignment = .centerY
        swatches.spacing = 6
        colorButtons.forEach(swatches.addArrangedSubview)
        let colorRow = SettingsRowView(title: "默认颜色")
        colorRow.trailingStack.addArrangedSubview(swatches)

        // 线宽改成数值步进：档位只能覆盖 2 / 4 / 8，而线宽本身是 1–40 的连续值
        let width = NSStepper()
        width.minValue = Double(SnipLineWidthStepper.range.lowerBound)
        width.maxValue = Double(SnipLineWidthStepper.range.upperBound)
        width.increment = 1
        width.valueWraps = false
        width.target = self
        width.action = #selector(widthChanged)
        width.setAccessibilityLabel("标注默认线宽")
        widthControl = width
        let widthValue = MenuPanelLabel.text("4 pt", font: SettingsTheme.rowValueFont,
                                             color: SettingsTheme.textSecondary)
        widthValue.alignment = .right
        widthValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        widthValueLabel = widthValue
        let widthStack = NSStackView(views: [widthValue, width])
        widthStack.orientation = .horizontal
        widthStack.alignment = .centerY
        widthStack.spacing = 6
        let widthRow = SettingsRowView(title: "线宽",
                                       subtitle: "1–40 pt 连续可调；截图里用 [ ] / 滚轮微调")
        widthRow.trailingStack.addArrangedSubview(widthStack)

        // 虚线开关：键 snip.annotationDashed 一直被覆盖层消费，但设置页从来没有入口
        let dash = NSSwitch()
        dash.target = self
        dash.action = #selector(dashedChanged)
        dash.setAccessibilityLabel("标注默认虚线")
        dashedSwitch = dash
        let dashRow = SettingsRowView(title: "虚线",
                                      subtitle: "矩形 / 椭圆 / 直线 / 箭头的默认线型")
        dashRow.trailingStack.addArrangedSubview(dash)

        // 文字字号：过去字号由线宽推导，设置页没有独立的字号入口
        let fontSize = NSStepper()
        fontSize.minValue = Double(SnipTextStyle.fontSizeRange.lowerBound)
        fontSize.maxValue = Double(SnipTextStyle.fontSizeRange.upperBound)
        fontSize.increment = 1
        fontSize.valueWraps = false
        fontSize.target = self
        fontSize.action = #selector(fontSizeChanged)
        fontSize.setAccessibilityLabel("文字标注默认字号")
        fontSizeControl = fontSize
        let fontSizeValue = MenuPanelLabel.text("20 pt", font: SettingsTheme.rowValueFont,
                                                color: SettingsTheme.textSecondary)
        fontSizeValue.alignment = .right
        fontSizeValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        fontSizeValueLabel = fontSizeValue
        let fontSizeStack = NSStackView(views: [fontSizeValue, fontSize])
        fontSizeStack.orientation = .horizontal
        fontSizeStack.alignment = .centerY
        fontSizeStack.spacing = 6
        let fontSizeRow = SettingsRowView(title: "文字字号",
                                          subtitle: "与线宽解耦；截图里用 0 / 9 或滚轮微调")
        fontSizeRow.trailingStack.addArrangedSubview(fontSizeStack)

        let card = SettingsCardView()
        card.addRow(colorRow)
        card.addRow(widthRow)
        card.addRow(dashRow)
        card.addRow(fontSizeRow)
        addEffectStyleRows(to: card)
        page.addCard(card, sectionTitle: "标注")
    }

    // MARK: - 回灌

    /// 标注样式三个控件（线宽 / 虚线 / 字号）的回灌
    func refreshAnnotationStyle() {
        let width = SnipLineWidthRange.clamp(
            (storage.object(forKey: SnipPreferenceKey.annotationLineWidth) as? Double)
                .map { CGFloat($0) } ?? SnipAnnotationStyleResolver.defaultLineWidth)
        widthControl?.doubleValue = Double(width)
        widthValueLabel?.stringValue = SnipPanelLabelText.width(width)

        dashedSwitch?.state = storage.bool(forKey: SnipPreferenceKey.annotationDashed) ? .on : .off

        let text = SnipTextStylePreference.load(storage: storage)
        // 字号显示的应当是「这支笔真正会用的字号」：缺键时回落到线宽推导值，
        // 而不是显示一个隐藏的 20 —— 用户点一下 stepper 才会把 20 写成绝对值，前后不一致。
        let fontSize = text.fontSize ?? max(width * 5, 14)
        fontSizeControl?.doubleValue = Double(fontSize)
        fontSizeValueLabel?.stringValue = SnipPanelLabelText.width(fontSize)
        refreshEffectStyleRows()
    }

    /// 调色板选中态
    ///
    /// 按 RGB 比对：偏好里的 hex 现在可能带 alpha（#RRGGBBAA），
    /// 直接整串比对会让「调过半透明的红」在设置页变成「一个都没选中」。
    func updateColorSelection() {
        let hex = storage.string(forKey: SnipPreferenceKey.annotationColor) ?? Self.defaultColorHex
        let selectedIndex = Self.palette.firstIndex {
            $0.hex.caseInsensitiveCompare(hex) == .orderedSame
                || SnipAnnotationColorHex.rgbHex($0.color).caseInsensitiveCompare(
                    SnipAnnotationColorHex.rgbHex(SnipAnnotationStyleResolver.color(fromHex: hex) ?? $0.color)
                ) == .orderedSame
        } ?? 0
        for (index, button) in colorButtons.enumerated() {
            let isSelected = index == selectedIndex
            button.layer?.borderWidth = isSelected ? 2 : 1
            // 选中描边用主题强调色，未选中用 1pt 分隔线色（都不再用系统 separatorColor：它不随主题变）
            button.layer?.borderColor = (isSelected ? SettingsTheme.accent : SettingsTheme.hairline).cgColor
        }
    }

    // MARK: - 动作

    @objc func widthChanged() {
        let width = SnipLineWidthRange.clamp(CGFloat(widthControl?.doubleValue ?? 4))
        storage.set(Double(width), forKey: SnipPreferenceKey.annotationLineWidth)
        widthValueLabel?.stringValue = SnipPanelLabelText.width(width)
        logger.info("标注默认线宽：" + SnipPanelLabelText.width(width))
    }

    @objc func dashedChanged() {
        let dashed = dashedSwitch?.state == .on
        storage.set(dashed, forKey: SnipPreferenceKey.annotationDashed)
        logger.info("标注默认线型：" + (dashed ? "虚线" : "实线"))
    }

    @objc func fontSizeChanged() {
        let size = SnipTextStyle.clampFontSize(CGFloat(fontSizeControl?.doubleValue ?? 20))
        var text = SnipTextStylePreference.load(storage: storage)
        text.fontSize = size
        SnipTextStylePreference.save(text, storage: storage)
        fontSizeValueLabel?.stringValue = SnipPanelLabelText.width(size)
        logger.info("文字标注默认字号：" + SnipPanelLabelText.width(size))
    }
}
