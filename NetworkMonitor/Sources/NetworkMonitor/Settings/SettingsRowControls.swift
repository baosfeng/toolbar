import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 设置页的行内控件小工具

/// 设置页行尾控件的构造原语：数值步进器、「数值 + 步进器」横排、色块
///
/// 单独成文件：这些是与具体卡片无关的构造原语，卡片只决定「摆哪几行、写哪个键」。
/// 文件名不带 `SettingsCapturePane` 前缀，因此单独成族、不占标注卡片的额度。
extension SettingsCapturePane {

    /// 数值步进器（线宽 / 字号 / 马赛克 / 模糊四行共用同一套外观与行为）
    func makeStepper(min: CGFloat, max: CGFloat, action: Selector) -> NSStepper {
        let stepper = NSStepper()
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
        return stepper
    }

    /// 右对齐的数值文本（等宽数字，宽度固定，数值变化时不推挤左侧）
    func makeValueLabel(_ text: String) -> NSTextField {
        let label = MenuPanelLabel.text(text, font: SettingsTheme.rowValueFont,
                                        color: SettingsTheme.textSecondary)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return label
    }

    /// 「数值 + 步进器」横排
    func makeStepperStack(value: NSTextField, stepper: NSStepper) -> NSStackView {
        let stack = NSStackView(views: [value, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    /// 调色板色块 — 22pt 圆形；选中态 2pt 强调色描边，未选中 1pt 分隔线（白色块在浅色下可见）
    func buildColorButtons() {
        for (index, entry) in Self.palette.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(colorChanged(_:)))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            button.layer?.backgroundColor = NSColor(srgbRed: entry.color.red,
                                                    green: entry.color.green,
                                                    blue: entry.color.blue,
                                                    alpha: entry.color.alpha).cgColor
            button.tag = index
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            button.setAccessibilityLabel("标注默认颜色：\(entry.name)")
            colorButtons.append(button)
        }
    }
}
