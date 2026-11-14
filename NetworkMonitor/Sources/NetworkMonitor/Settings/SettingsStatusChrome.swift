import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 页头状态胶囊（拆出自 SettingsTheme.swift：令牌文件已贴着 15 KiB 上限）

extension SettingsTheme {

    /// 胶囊宽度 = 左右内边距 + 状态点 + 点与文案间距 + 文案实测宽
    ///
    /// 为什么自己算宽度：胶囊是「自绘底 + 一行等宽文案」，宽度交给 Auto Layout
    /// 从标签内在宽反推会在没有竞争方时被压成 0（实测文案不可见）；
    /// 文案是定长静态串，按等宽字体量出来最稳，三套主题下宽度也一致。
    static func statusChipWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: statusChipFont]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        return statusChipPaddingX * 2 + statusDotSize + statusDotSpacing + ceil(textWidth)
    }
}

/// 页头状态胶囊 —— bandFill 底 + 0.5pt cardStroke + 前置 7pt 状态点 + 10.5pt 等宽文案
///
/// 口径：**一个胶囊只表达「一个主语 + 一个状态」**；没有真实状态的页不放胶囊
/// （空胶囊等于噪音）。文案拼接是 UI 库里的纯函数，这里只负责画。
///
/// 底、状态点、文案全部在 `draw` 里画：
/// - 不复用 `SettingsStatusDotView`：那把颜色写进 `CALayer.backgroundColor`（静态 CGColor），
///   换主题时不改外观、只改了角色映射，点会停在旧主题色；画在 `draw` 里每次重绘都重新解析。
/// - 不用 `NSTextField` 标签：无竞争方的宽约束会把标签压成 0（实测文案不可见），
///   自绘一行等宽文字既省一层视图，也保证换主题后文字色同步。
final class SettingsStatusChipView: NSView {

    /// 当前语义（nil = 不画状态点）
    private var tone: SettingsStatusTone?
    /// 当前文案（空串 = 不显示）
    private var text = ""
    private var widthConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        let width = widthAnchor.constraint(equalToConstant: 0)
        widthConstraint = width
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsTheme.statusBandHeight),
            width,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新胶囊内容（nil = 不显示：本页没有真实状态就别挂空胶囊）
    func update(_ chip: SettingsStatusChip?) {
        let newText = chip?.text ?? ""
        isHidden = newText.isEmpty
        text = newText
        tone = chip?.tone
        widthConstraint?.constant = SettingsTheme.statusChipWidth(for: newText)
        setAccessibilityLabel(newText.isEmpty ? nil : newText)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = SettingsTheme.statusBandRadius
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        SettingsTheme.bandFill.setFill()
        path.fill()
        // 0.5pt 描边取角色自带的 10% 透明度，与卡片同一档
        SettingsTheme.cardStroke.setStroke()
        let strokePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                      xRadius: radius, yRadius: radius)
        strokePath.lineWidth = SettingsTheme.cardStrokeWidth
        strokePath.stroke()

        // 前置状态点（7pt 实心圆，垂直居中）
        let diameter = SettingsTheme.statusDotSize
        if let tone {
            let dotRect = NSRect(x: SettingsTheme.statusChipPaddingX,
                                 y: bounds.midY - diameter / 2,
                                 width: diameter, height: diameter)
            SettingsTheme.statusDotColor(tone).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: SettingsTheme.statusChipFont,
            .foregroundColor: SettingsTheme.textSecondary,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: SettingsTheme.statusChipPaddingX + diameter + SettingsTheme.statusDotSpacing,
            y: bounds.midY - textSize.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
