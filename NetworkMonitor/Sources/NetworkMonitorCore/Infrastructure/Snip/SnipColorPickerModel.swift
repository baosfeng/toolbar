import CoreGraphics
import Foundation

// MARK: - 取色器口径（纯逻辑，可单测）

/// 自绘取色板的数值口径 —— HSV 与 RGB 互转、色相条 / 透明度条的命中换算
///
/// 为什么要自己做：覆盖层跑在 `screenSaver` 层级，原生 `NSColorPanel` / `NSPopover`
/// 会被压在下面，而且原生控件会抢走键盘焦点（截图态下按键必须留在覆盖层）。
/// 因此取色板只能自绘，而自绘就要自己维护一套 HSV ↔ RGB 的换算。
///
/// 与 SnipAnnotationColor（0…1 浮点 RGB）对接：HSV 只在取色板里用，落笔时立刻转回 RGB。
public struct SnipHSVColor: Equatable, Sendable {
    /// 色相 0…1（0 = 红）
    public var hue: CGFloat
    /// 饱和度 0…1
    public var saturation: CGFloat
    /// 明度 0…1
    public var brightness: CGFloat
    /// 透明度 0…1
    public var alpha: CGFloat

    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1) {
        self.hue = Self.wrap(hue)
        self.saturation = min(max(saturation, 0), 1)
        self.brightness = min(max(brightness, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    /// 色相按 1 取模（负数也绕回正区间）
    static func wrap(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    /// HSV → RGB
    public var rgb: SnipAnnotationColor {
        let h = hue * 6
        let sector = Int(h.rounded(.down)) % 6
        let f = h - h.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - f * saturation)
        let t = brightness * (1 - (1 - f) * saturation)
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch sector {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        return SnipAnnotationColor(red: r, green: g, blue: b, alpha: alpha)
    }

    /// RGB → HSV（灰色时色相取 0，与取色板色相条停位一致）
    public init(_ color: SnipAnnotationColor) {
        let maxValue = max(color.red, color.green, color.blue)
        let minValue = min(color.red, color.green, color.blue)
        let delta = maxValue - minValue
        var hue: CGFloat = 0
        if delta > 0 {
            if maxValue == color.red {
                hue = ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == color.green {
                hue = (color.blue - color.red) / delta + 2
            } else {
                hue = (color.red - color.green) / delta + 4
            }
            hue /= 6
        }
        self.init(hue: hue,
                  saturation: maxValue <= 0 ? 0 : delta / maxValue,
                  brightness: maxValue,
                  alpha: color.alpha)
    }
}

// MARK: - 取色板几何

/// 取色板的命中换算 —— 视图与测试共用一份，避免「画的位置」与「点到的位置」两套算法
public enum SnipColorPickerGeometry {

    /// 色相条的总段数（用一条渐变画出来的六段色环）
    public static let hueSegments = 6

    /// 把一个点在单位方块里的位置换算成饱和度 / 明度（左上 = 白，右上 = 纯色，底部 = 黑）
    public static func saturationBrightness(atUnit point: CGPoint) -> (saturation: CGFloat, brightness: CGFloat) {
        (saturation: min(max(point.x, 0), 1),
         brightness: 1 - min(max(point.y, 0), 1))
    }

    /// 饱和度 / 明度 → 单位方块里的位置（画选中环用）
    public static func unitPoint(saturation: CGFloat, brightness: CGFloat) -> CGPoint {
        CGPoint(x: min(max(saturation, 0), 1), y: 1 - min(max(brightness, 0), 1))
    }

    /// 横向条上的位置换算成 0…1 的比例（色相条与透明度条共用）
    public static func ratio(atX x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1)
    }

    // MARK: - 面板几何（视图与测试共用）

    /// 面板内边距
    public static let padding: CGFloat = 10
    /// 饱和度/明度方块边长
    public static let squareSide: CGFloat = 168
    /// 横向条高度
    public static let barHeight: CGFloat = 12
    /// 条与条 / 条与方块之间的间距
    public static let gap: CGFloat = 10
    /// 底部一行（hex 文本 + 完成按钮）的高度
    public static let footerHeight: CGFloat = 22
    /// 底部「完成」按钮占的宽度
    public static let footerButtonWidth: CGFloat = 56

    /// 整块面板尺寸：内边距 + 方块 + 两条滑条 + 底部一行
    public static var panelSize: CGSize {
        CGSize(width: squareSide + padding * 2,
               height: padding * 2 + squareSide + gap * 2 + barHeight * 2 + gap + footerHeight)
    }

    /// 饱和度/明度方块在面板内的矩形
    public static func squareRect(inPanelWithHeight height: CGFloat) -> CGRect {
        CGRect(x: padding, y: padding, width: squareSide, height: squareSide)
    }

    /// 色相条矩形（方块正下方）
    public static func hueRect(squareRect: CGRect) -> CGRect {
        CGRect(x: squareRect.minX, y: squareRect.maxY + gap, width: squareRect.width, height: barHeight)
    }

    /// 透明度条矩形（色相条正下方）
    public static func alphaRect(hueRect: CGRect) -> CGRect {
        CGRect(x: hueRect.minX, y: hueRect.maxY + gap, width: hueRect.width, height: barHeight)
    }

    /// 底部 hex 文本矩形（透明度条正下方，右侧留给「完成」）
    public static func footerRect(alphaRect: CGRect) -> CGRect {
        CGRect(x: alphaRect.minX,
               y: alphaRect.maxY + gap,
               width: alphaRect.width - footerButtonWidth,
               height: footerHeight)
    }
}
