import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 自绘取色板

/// 覆盖层里的取色板 —— 色相条 + 饱和度/明度方块 + 透明度条
///
/// 为什么自绘：覆盖层跑在 `screenSaver` 层级，原生 `NSColorPanel` 会被压在下面；
/// 原生控件还会抢走键盘焦点（截图态下按键必须留在覆盖层）。口径全部在 Core 的
/// `SnipHSVColor` / `SnipColorPickerGeometry`，这里只负责画与收鼠标。
@MainActor
final class SnipColorPickerView: NSView {

    /// 取色中（连续回调，用于实时刷新工具条当前色）
    var onColorChanged: ((SnipAnnotationColor) -> Void)?
    /// 收起
    var onClose: (() -> Void)?

    /// 当前 HSV 值
    private(set) var color: SnipHSVColor

    /// 正在拖的是哪一块（-1 = 没有）
    private var dragging: Zone = .none

    private enum Zone: Int {
        case none = -1
        case saturationBrightness = 0
        case hue = 1
        case alpha = 2
    }

    // MARK: 几何（口径在 Core 的 SnipColorPickerGeometry，视图与测试共用一份）

    /// 面板尺寸
    static var panelSize: CGSize { SnipColorPickerGeometry.panelSize }

    private var squareRect: CGRect {
        SnipColorPickerGeometry.squareRect(inPanelWithHeight: bounds.height)
    }

    private var hueRect: CGRect {
        SnipColorPickerGeometry.hueRect(squareRect: squareRect)
    }

    private var alphaRect: CGRect {
        SnipColorPickerGeometry.alphaRect(hueRect: hueRect)
    }

    /// 底部 hex 文本区（点它把色值复制到剪贴板）
    var hexRect: CGRect {
        SnipColorPickerGeometry.footerRect(alphaRect: alphaRect)
    }

    init(color: SnipAnnotationColor) {
        self.color = SnipHSVColor(color)
        super.init(frame: NSRect(origin: .zero, size: Self.panelSize))
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("取色板（色相 / 饱和度 / 明度 / 透明度）")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    override var isFlipped: Bool { true }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        drawSquare()
        drawHueBar()
        drawAlphaBar()
        drawFooter()
    }

    /// 饱和度（横）× 明度（纵）方块：左上白 → 右上纯色 → 底部黑
    private func drawSquare() {
        let rect = squareRect
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // 底色 = 当前色相的全饱和纯色，再叠一层 白→透明 的横向渐变与 透明→黑 的纵向渐变
        let pure = SnipHSVColor(hue: color.hue, saturation: 1, brightness: 1, alpha: 1).rgb
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(NSColor(cgColor: pure.cgColor)?.cgColor ?? NSColor.white.cgColor)
        context.fill(rect)
        let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.minX, y: rect.midY),
                                       end: CGPoint(x: rect.maxX, y: rect.midY),
                                       options: [])
        }
        let darkColors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: darkColors as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.midX, y: rect.minY),
                                       end: CGPoint(x: rect.midX, y: rect.maxY),
                                       options: [])
        }
        context.restoreGState()
        // 选中环
        let point = SnipColorPickerGeometry.unitPoint(saturation: color.saturation,
                                                      brightness: color.brightness)
        let center = CGPoint(x: rect.minX + point.x * rect.width,
                             y: rect.minY + point.y * rect.height)
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        ring.lineWidth = 2
        ring.stroke()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let outer = NSBezierPath(ovalIn: CGRect(x: center.x - 7.5, y: center.y - 7.5, width: 15, height: 15))
        outer.lineWidth = 1
        outer.stroke()
    }

    /// 色相条：六段渐变
    private func drawHueBar() {
        let rect = hueRect
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: Self.hueGradientColors as CFArray,
                                        locations: [0, 1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 5.0 / 6, 1]) else { return }
        context.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.midY),
                                   end: CGPoint(x: rect.maxX, y: rect.midY),
                                   options: [])
        context.restoreGState()
        drawKnob(atRatio: color.hue, in: rect)
    }

    /// 透明度条：当前色 不透明 → 透明，底下垫棋盘格
    private func drawAlphaBar() {
        let rect = alphaRect
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()
        SnipBarDrawing.drawChecker(in: rect, in: context)
        let opaque = SnipHSVColor(hue: color.hue, saturation: color.saturation,
                                  brightness: color.brightness, alpha: 1).rgb
        let clear = SnipAnnotationColor(red: opaque.red, green: opaque.green, blue: opaque.blue, alpha: 0)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [NSColor(cgColor: opaque.cgColor)?.cgColor ?? NSColor.white.cgColor,
                                              NSColor(cgColor: clear.cgColor)?.cgColor ?? NSColor.clear.cgColor] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.minX, y: rect.midY),
                                       end: CGPoint(x: rect.maxX, y: rect.midY),
                                       options: [])
        }
        context.restoreGState()
        drawKnob(atRatio: color.alpha, in: rect)
    }

    /// 条的滑块
    private func drawKnob(atRatio ratio: CGFloat, in rect: CGRect) {
        let x = rect.minX + ratio * rect.width
        let knob = CGRect(x: x - 3, y: rect.minY - 2, width: 6, height: rect.height + 4)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
        NSColor.black.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(roundedRect: knob.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        border.lineWidth = 1
        border.stroke()
    }

    /// 底部：hex 文本 + 关闭按钮
    private func drawFooter() {
        let hex = SnipAnnotationColorHex.hex(color.rgb)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
        ]
        (hex as NSString).draw(at: CGPoint(x: hexRect.minX, y: hexRect.midY - 7),
                               withAttributes: attributes)
        let close = "完成" as NSString
        let closeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
        ]
        let size = close.size(withAttributes: closeAttributes)
        close.draw(at: CGPoint(x: bounds.maxX - SnipColorPickerGeometry.padding - size.width,
                               y: hexRect.midY - size.height / 2),
                   withAttributes: closeAttributes)
    }

    // MARK: - 交互

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if squareRect.contains(point) {
            dragging = .saturationBrightness
            applyDrag(at: point)
        } else if hueRect.contains(point) {
            dragging = .hue
            applyDrag(at: point)
        } else if alphaRect.contains(point) {
            dragging = .alpha
            applyDrag(at: point)
        } else if hexRect.contains(point) {
            // 点色值 = 复制，与 Snipaste 取色后直接粘贴的习惯一致
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(SnipAnnotationColorHex.hex(color.rgb), forType: .string)
        } else {
            onClose?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        applyDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        dragging = .none
    }

    /// 按当前拖动区块把点换算成 HSV 分量
    private func applyDrag(at point: CGPoint) {
        switch dragging {
        case .saturationBrightness:
            let rect = squareRect
            let unit = CGPoint(x: (point.x - rect.minX) / max(rect.width, 1),
                               y: (point.y - rect.minY) / max(rect.height, 1))
            let pair = SnipColorPickerGeometry.saturationBrightness(atUnit: unit)
            color.saturation = pair.saturation
            color.brightness = pair.brightness
        case .hue:
            let rect = hueRect
            color.hue = SnipColorPickerGeometry.ratio(atX: point.x - rect.minX, width: rect.width)
        case .alpha:
            let rect = alphaRect
            color.alpha = SnipColorPickerGeometry.ratio(atX: point.x - rect.minX, width: rect.width)
        case .none:
            return
        }
        needsDisplay = true
        onColorChanged?(color.rgb)
    }

    /// 色相条的七段色标
    private static let hueGradientColors: [CGColor] = {
        (0...6).map { index in
            SnipHSVColor(hue: CGFloat(index) / 6, saturation: 1, brightness: 1, alpha: 1).rgb.cgColor
        }
    }()
}
