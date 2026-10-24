import CoreGraphics

// MARK: - 选区交互状态机

/// 截图覆盖层的选区交互状态机 — 纯逻辑，不依赖 AppKit
///
/// 坐标一律为「本地点坐标」（左上原点，单位点）；跨屏换算由调用方用
/// SelectionGeometry 的 display frame 叠加完成。
public struct SnipSelectionState: Equatable, Sendable {

    /// 交互阶段
    public enum Phase: Equatable, Sendable {
        /// 未开始
        case idle
        /// 正在拖拽新建
        case dragging
        /// 已成立，可移动或调整
        case selected
    }

    /// 可拖拽的把手
    public enum Handle: Equatable, Sendable {
        case move
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }

    public private(set) var phase: Phase = .idle
    public private(set) var rect: CGRect = .zero

    /// 成立选区的最小边长（点）
    public var minimumSide: CGFloat = 1

    private var dragAnchor: CGPoint = .zero
    private var adjustHandle: Handle?
    private var adjustOrigin: CGRect = .zero
    private var adjustPointer: CGPoint = .zero

    public init() {}

    /// 已成立的选区（仅 selected 阶段有值）
    public var selection: CGRect? {
        phase == .selected ? rect : nil
    }

    // MARK: - 新建

    public mutating func begin(at point: CGPoint) {
        phase = .dragging
        dragAnchor = point
        rect = .zero
    }

    public mutating func drag(to point: CGPoint) {
        guard phase == .dragging else { return }
        rect = SelectionGeometry.normalize(from: dragAnchor, to: point)
    }

    public mutating func end() {
        guard phase == .dragging else { return }
        let isValid = rect.width >= minimumSide && rect.height >= minimumSide
        phase = isValid ? .selected : .idle
        if !isValid { rect = .zero }
    }

    /// 直接成立一个选区（窗口检测点选时使用）
    public mutating func select(_ rect: CGRect) {
        guard rect.width >= minimumSide, rect.height >= minimumSide else { return }
        phase = .selected
        self.rect = rect
    }

    // MARK: - 移动与调整

    public mutating func beginAdjust(_ handle: Handle, at point: CGPoint) {
        guard phase == .selected else { return }
        adjustHandle = handle
        adjustOrigin = rect
        adjustPointer = point
    }

    public mutating func adjust(to point: CGPoint, lockingAspect: Bool = false) {
        guard phase == .selected, let handle = adjustHandle else { return }
        let dx = point.x - adjustPointer.x
        let dy = point.y - adjustPointer.y
        if lockingAspect {
            rect = SnipAspectLock.lockedResize(handle: handle,
                                               origin: adjustOrigin,
                                               dx: dx,
                                               dy: dy,
                                               minimum: minimumSide)
        } else {
            rect = Self.apply(handle: handle, to: adjustOrigin, dx: dx, dy: dy, minimum: minimumSide)
        }
    }

    public mutating func endAdjust() {
        adjustHandle = nil
    }

    /// 键盘整块移动
    public mutating func move(by delta: CGSize) {
        guard phase == .selected else { return }
        rect = rect.offsetBy(dx: delta.width, dy: delta.height)
    }

    /// 四边向外扩（保持中心不动）
    public mutating func expand(by delta: CGFloat) {
        guard phase == .selected else { return }
        rect = rect.insetBy(dx: -delta, dy: -delta)
    }

    /// 四边向内缩（保持中心不动），不小于最小边长
    public mutating func shrink(by delta: CGFloat) {
        guard phase == .selected else { return }
        let inset = min(delta, (rect.width - minimumSide) / 2, (rect.height - minimumSide) / 2)
        guard inset > 0 else { return }
        rect = rect.insetBy(dx: inset, dy: inset)
    }

    /// 回到未开始
    public mutating func reset() {
        phase = .idle
        rect = .zero
        adjustHandle = nil
    }

    // MARK: - 命中判定

    /// 命中把手 — 角优先，其次边，最后内部移动；未成立时返回 nil
    public func hitTest(_ point: CGPoint, handleSize: CGFloat) -> Handle? {
        guard phase == .selected, rect.width > 0, rect.height > 0 else { return nil }
        let half = handleSize / 2
        let corners: [(Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))
        ]
        for (handle, center) in corners where abs(point.x - center.x) <= half && abs(point.y - center.y) <= half {
            return handle
        }
        let edges: [(Handle, CGPoint)] = [
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY))
        ]
        for (handle, center) in edges where abs(point.x - center.x) <= half && abs(point.y - center.y) <= half {
            return handle
        }
        return rect.contains(point) ? .move : nil
    }

    // MARK: - 把手几何

    /// 由把手与原矩形、位移得到新矩形；宽高低于最小值时夹住对应边
    public static func apply(handle: Handle, to origin: CGRect, dx: CGFloat, dy: CGFloat, minimum: CGFloat) -> CGRect {
        var minX = origin.minX
        var maxX = origin.maxX
        var minY = origin.minY
        var maxY = origin.maxY

        switch handle {
        case .move:
            return origin.offsetBy(dx: dx, dy: dy)
        case .topLeft:
            minX += dx; minY += dy
        case .top:
            minY += dy
        case .topRight:
            maxX += dx; minY += dy
        case .left:
            minX += dx
        case .right:
            maxX += dx
        case .bottomLeft:
            minX += dx; maxY += dy
        case .bottom:
            maxY += dy
        case .bottomRight:
            maxX += dx; maxY += dy
        }

        if maxX - minX < minimum {
            if handle == .left || handle == .topLeft || handle == .bottomLeft {
                minX = maxX - minimum
            } else {
                maxX = minX + minimum
            }
        }
        if maxY - minY < minimum {
            if handle == .top || handle == .topLeft || handle == .topRight {
                minY = maxY - minimum
            } else {
                maxY = minY + minimum
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
