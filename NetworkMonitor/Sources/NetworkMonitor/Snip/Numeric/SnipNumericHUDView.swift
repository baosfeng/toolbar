import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 数值 HUD 视图

/// 跟随光标显示当前数值的小气泡
///
/// 自绘而不是 NSTextField：覆盖层跑在 screenSaver 层级，任何原生控件都会抢键盘焦点，
/// 而调整数值期间按键必须留在覆盖层（否则下一格滚轮之后按键就打到别处去了）。
///
/// 高度与宽度由 `SnipNumericHUD` 给出的文案实时算：这是个"随时变字"的控件，
/// 固定宽度会让「线宽 4 pt」与「马赛克 14 px · 精调」一个偏左一个偏右。
@MainActor
final class SnipNumericHUDView: NSView {

    private(set) var entry: SnipNumericHUD.Entry?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.staticText)
        // 读屏：数值变化要能被读出来，否则这个反馈只对看得见的人有效
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    /// 更新展示内容并按文案重算尺寸
    ///
    /// 返回新的尺寸：调用方据此重新摆放（气泡在屏幕边缘时会被翻到光标另一侧）。
    @discardableResult
    func show(_ entry: SnipNumericHUD.Entry) -> CGSize {
        self.entry = entry
        setAccessibilityLabel(SnipNumericHUD.text(for: entry))
        let size = Self.size(for: entry)
        if frame.size != size {
            frame.size = size
        }
        needsDisplay = true
        return size
    }

    /// 清空（不再画任何东西）
    func clear() {
        entry = nil
        setAccessibilityLabel(nil)
        needsDisplay = true
    }

    /// 按文案算气泡尺寸（与绘制共用同一份字体度量）
    static func size(for entry: SnipNumericHUD.Entry) -> CGSize {
        let text = SnipNumericHUD.text(for: entry) as NSString
        let measured = text.size(withAttributes: attributes)
        return CGSize(width: ceil(measured.width) + SnipNumericHUD.padding.width * 2,
                      height: ceil(measured.height) + SnipNumericHUD.padding.height * 2)
    }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let entry else { return }
        let path = NSBezierPath(roundedRect: bounds,
                                xRadius: SnipNumericHUD.cornerRadius,
                                yRadius: SnipNumericHUD.cornerRadius)
        NSColor.black.withAlphaComponent(0.78).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        let text = SnipNumericHUD.text(for: entry) as NSString
        text.draw(at: CGPoint(x: SnipNumericHUD.padding.width,
                              y: SnipNumericHUD.padding.height),
                  withAttributes: Self.attributes)
    }
}
