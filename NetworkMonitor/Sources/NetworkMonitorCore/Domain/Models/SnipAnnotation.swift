import CoreGraphics

// MARK: - 标注颜色

/// 标注颜色 — 用 0…1 的浮点分量，避免 UInt8 与 CGColor 来回转换
public struct SnipAnnotationColor: Equatable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = SnipAnnotationColor(red: 0.92, green: 0.20, blue: 0.19)
    public static let orange = SnipAnnotationColor(red: 0.96, green: 0.55, blue: 0.14)
    public static let yellow = SnipAnnotationColor(red: 0.98, green: 0.82, blue: 0.18)
    public static let green = SnipAnnotationColor(red: 0.20, green: 0.72, blue: 0.35)
    public static let blue = SnipAnnotationColor(red: 0.16, green: 0.50, blue: 0.95)
    public static let black = SnipAnnotationColor(red: 0.10, green: 0.10, blue: 0.10)
    public static let white = SnipAnnotationColor(red: 1, green: 1, blue: 1)

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - 标注样式

public struct SnipAnnotationStyle: Equatable, Sendable {
    public var color: SnipAnnotationColor
    public var lineWidth: CGFloat
    /// 矩形 / 椭圆是否为实心填充
    public var filled: Bool
    /// 是否用虚线
    public var dashed: Bool

    public init(color: SnipAnnotationColor = .red,
                lineWidth: CGFloat = 3,
                filled: Bool = false,
                dashed: Bool = false) {
        self.color = color
        self.lineWidth = lineWidth
        self.filled = filled
        self.dashed = dashed
    }
}

// MARK: - 标注图元

public enum SnipAnnotationKind: String, Equatable, Sendable, CaseIterable {
    case rectangle
    case ellipse
    case line
    case polyline
    case arrow
    case freehand
    case mosaic
    case blur
    case text

    public var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .line: return "直线"
        case .polyline: return "折线"
        case .arrow: return "箭头"
        case .freehand: return "画笔"
        case .mosaic: return "马赛克"
        case .blur: return "模糊"
        case .text: return "文字"
        }
    }

    /// 这两类需要底图像素，由合成器单独处理
    public var needsBaseImage: Bool {
        self == .mosaic || self == .blur
    }

    /// 是否是可拖拽绘制的图元（文字走点击输入，橡皮擦是操作）
    public var isDrawable: Bool {
        self != .text
    }
}

/// 一个标注图元 — 坐标为本地点坐标（左上原点）
public struct SnipAnnotation: Equatable, Sendable {
    public let kind: SnipAnnotationKind
    /// 起点（矩形 / 椭圆为拖拽起点）
    public var start: CGPoint
    /// 终点（矩形 / 椭圆为拖拽终点）
    public var end: CGPoint
    /// 画笔轨迹点（仅 freehand 使用）
    public var points: [CGPoint]
    /// 文字内容（仅 text 使用）
    public var text: String
    /// 文字字号倍数（滚轮缩放，1 = 基准字号）
    public var fontScale: CGFloat = 1
    /// 文字旋转弧度（⌘R 每次加 90°）
    public var rotation: CGFloat = 0
    public var style: SnipAnnotationStyle

    public init(kind: SnipAnnotationKind,
                start: CGPoint,
                end: CGPoint,
                points: [CGPoint] = [],
                text: String = "",
                style: SnipAnnotationStyle = SnipAnnotationStyle()) {
        self.kind = kind
        self.start = start
        self.end = end
        self.points = points.isEmpty ? [start, end] : points
        self.text = text
        self.style = style
    }

    /// 由起止点归一化出的包围盒
    public var boundingRect: CGRect {
        SnipSelectionGeometry.normalize(from: start, to: end)
    }

    /// 文字字号：由当前线宽推出来，再乘缩放倍数
    public var fontSize: CGFloat {
        max(style.lineWidth * 5, 14) * fontScale
    }

    /// 是否小到可以丢弃（误触）
    public func isDegenerate(minimumSide: CGFloat = 2) -> Bool {
        if kind == .text {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if kind == .freehand || kind == .polyline {
            return points.count < 2
        }
        return boundingRect.width < minimumSide && boundingRect.height < minimumSide
    }
}

// MARK: - 归一化（避免与 SelectionGeometry 循环引用）

/// 内部使用的极小几何工具
enum SnipSelectionGeometry {
    static func normalize(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }
}
