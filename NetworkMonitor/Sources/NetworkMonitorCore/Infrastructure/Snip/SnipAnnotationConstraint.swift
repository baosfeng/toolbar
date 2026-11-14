import CoreGraphics
import Foundation

// MARK: - Shift 标注约束（纯逻辑，可单测）

/// 按住 Shift 绘制标注时的形状约束
///
/// Snipaste「高级技巧」页原文：每一种标注形状，按下 Shift 可以变换功能 ——
/// 矩形 → 正方形、椭圆 → 圆形、直线 / 箭头 → 水平·垂直·45°、画笔 → 可中途变换为直线。
/// 早期实现只在「调整选区大小」时读 Shift，画标注时完全不读，用户按住 Shift 画不出正方形。
///
/// 约束只发生在**拖拽阶段**：中途按下要立刻生效（在 mouseDragged 里每次取当前修饰键重算），
/// 松开回到自由形状（下次拖拽重新从原始起点算，不会记住上一次的约束）。
public enum SnipAnnotationConstraint {

    /// 45° 吸附容差（弧度）— 接近水平 / 垂直 / 对角时才吸附，否则保持自由角度
    public static let diagonalTolerance: CGFloat = .pi / 12

    /// 把一次拖拽的终点按 Shift 约束修正
    ///
    /// - Parameters:
    ///   - kind: 正在绘制的图元类型（文字与折线不受约束）
    ///   - start: 拖拽起点（本地点坐标）
    ///   - end: 当前终点
    ///   - lockingShift: 当前是否按住 Shift
    public static func constrained(kind: SnipAnnotationKind,
                                   start: CGPoint,
                                   end: CGPoint,
                                   lockingShift: Bool) -> CGPoint {
        guard lockingShift else { return end }
        switch kind {
        case .rectangle, .mosaic, .blur:
            // 矩形类 → 正方形：取较长边，方向跟随原终点
            let side = max(abs(end.x - start.x), abs(end.y - start.y))
            guard side > 0 else { return end }
            let dx: CGFloat = end.x >= start.x ? side : -side
            let dy: CGFloat = end.y >= start.y ? side : -side
            return CGPoint(x: start.x + dx, y: start.y + dy)
        case .ellipse:
            // 椭圆 → 圆：与矩形同一口径（包围盒变正方形即得圆）
            return constrained(kind: .rectangle, start: start, end: end, lockingShift: true)
        case .line, .arrow:
            return snappedAngle(start: start, end: end)
        case .freehand:
            // 画笔中途按 Shift → 直线：由调用方在拖拽时直接清掉中间点，这里只约束终点
            return snappedAngle(start: start, end: end)
        case .text, .polyline, .number:
            // 文字/折线/序号不按 Shift 约束：序号是单击落点，没有拖拽方向可吸附
            return end
        }
    }

    /// 把终点吸附到最近的 0° / 45° / 90° / 135° 方向，长度保持不变
    ///
    /// 只吸附到这几条「整齐」的方向：用户想画任意角度的箭头时按住 Shift 反而更顺手，
    /// 但偶尔按住按松会跳角，因此容差取 π/12（15°）—— 只有接近整角时才吸附。
    public static func snappedAngle(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return end }
        let angle = atan2(dy, dx)
        let step = CGFloat.pi / 4
        let rounded = (angle / step).rounded() * step
        guard abs(angle - rounded) <= diagonalTolerance else { return end }
        return CGPoint(x: start.x + cos(rounded) * length,
                       y: start.y + sin(rounded) * length)
    }
}
