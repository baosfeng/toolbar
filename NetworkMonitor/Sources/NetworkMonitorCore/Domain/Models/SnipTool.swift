import Foundation

// MARK: - 标注工具

/// 工具条上的工具 — 除橡皮擦外都对应一种标注图元
public enum SnipTool: String, Equatable, Sendable, CaseIterable {
    case rectangle
    case ellipse
    case line
    case polyline
    case arrow
    case freehand
    case mosaic
    case blur
    case text
    case eraser

    /// 对应的图元类型；橡皮擦返回 nil（它是操作而不是图元）
    public var annotationKind: SnipAnnotationKind? {
        SnipAnnotationKind(rawValue: rawValue)
    }

    public var displayName: String {
        switch self {
        case .eraser: return "橡皮擦"
        default: return annotationKind?.displayName ?? rawValue
        }
    }

    /// 工具条使用 SF Symbols 名称
    public var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .polyline: return "scribble"
        case .arrow: return "arrow.up.right"
        case .freehand: return "pencil.tip"
        case .mosaic: return "square.grid.3x3.fill"
        case .blur: return "drop.halffull"
        case .text: return "character.textbox"
        case .eraser: return "eraser"
        }
    }
}
