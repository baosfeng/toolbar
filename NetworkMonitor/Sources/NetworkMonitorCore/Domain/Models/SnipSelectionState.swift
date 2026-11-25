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
    /// 拖拽中按空格进入「移动选区」时的锚：矩形快照与按下位置
    private var spaceAnchorRect: CGRect?
    private var spaceAnchorPoint: CGPoint = .zero

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
        spaceAnchorRect = nil
        let isValid = rect.width >= minimumSide && rect.height >= minimumSide
        phase = isValid ? .selected : .idle
        if !isValid { rect = .zero }
    }

    // MARK: - 拖拽中按空格切「移动选区」（Snipaste 高级技巧）

    /// 拖拽过程中按下空格 → 进入「移动已有选区」模式
    ///
    /// 官方口径：「不要松开鼠标，按下空格键即进入移动选区模式」。
    /// 动机很实在：拉选区拉到一半发现位置偏了，松手重来要丢掉刚对好的边。
    ///
    /// 只在 dragging 阶段生效：已成立的选区本来就能拖内部移动，不需要这条通路。
    /// - Returns: 是否真的进入了移动模式
    @discardableResult
    public mutating func enterSpaceMove() -> Bool {
        guard phase == .dragging, spaceAnchorRect == nil else { return false }
        guard rect.width >= minimumSide || rect.height >= minimumSide else { return false }
        spaceAnchorRect = rect
        spaceAnchorPoint = .zero
        return true
    }

    /// 是否处于「拖拽中按空格移动」模式
    public var isSpaceMoving: Bool { spaceAnchorRect != nil }

    /// 移动模式下跟随光标平移（第一次调用以当前点作为锚）
    public mutating func spaceMove(to point: CGPoint) {
        guard let anchorRect = spaceAnchorRect else { return }
        if spaceAnchorPoint == .zero {
            spaceAnchorPoint = point
            return
        }
        rect = anchorRect.offsetBy(dx: point.x - spaceAnchorPoint.x,
                                   dy: point.y - spaceAnchorPoint.y)
    }

    /// 退出移动模式（空格松开）：把拖拽锚点重新钉在当前位置，
    /// 之后的拖拽继续从这个矩形往外拉，而不是跳回按空格前的原始起点
    public mutating func exitSpaceMove(at point: CGPoint) {
        guard spaceAnchorRect != nil else { return }
        spaceAnchorRect = nil
        spaceAnchorPoint = .zero
        dragAnchor = point
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

    // MARK: - 单边扩缩（Snipaste 的 Ctrl/Shift + 方向键语义）

    /// 四条边里的一条 —— 单边扩缩的方向
    public enum Edge: Equatable, Sendable {
        case left, right, up, down
    }

    /// 把**对应那条边**向外推 delta（其余三边不动）
    ///
    /// 与 `expand(by:)` 的区别：那个是四边同时外扩（保持中心），
    /// 而 Snipaste 的 Ctrl+方向键是「只动那一条边」。截图时常要精确地
    /// 「右边再多带 1 像素」，四边同扩会把另一侧的像素也带进来。
    ///
    /// - Parameter bounds: 可选的屏幕范围，扩到屏幕外时按它裁住（不会扩出可视区）
    public mutating func expand(edge: Edge, by delta: CGFloat, within bounds: CGRect? = nil) {
        guard phase == .selected, delta > 0 else { return }
        var next = rect
        switch edge {
        case .left: next.origin.x -= delta; next.size.width += delta
        case .right: next.size.width += delta
        case .up: next.origin.y -= delta; next.size.height += delta
        case .down: next.size.height += delta
        }
        if let bounds {
            next = next.intersection(bounds)
            guard !next.isNull else { return }
        }
        rect = next
    }

    /// 把**对应那条边**向内收 delta（其余三边不动），不小于最小边长
    public mutating func shrink(edge: Edge, by delta: CGFloat, within bounds: CGRect? = nil) {
        guard phase == .selected, delta > 0 else { return }
        var next = rect
        switch edge {
        case .left: next.origin.x += delta; next.size.width -= delta
        case .right: next.size.width -= delta
        case .up: next.origin.y += delta; next.size.height -= delta
        case .down: next.size.height -= delta
        }
        // 判 size 而不是 .width：CGRect 的 .width 会把负宽标准化成正数，
        // 用 .width 判会让「缩过头」的矩形被当成合法值写回去（实测 10pt 缩 100pt 变 90pt）。
        guard next.size.width >= minimumSide, next.size.height >= minimumSide else { return }
        if let bounds {
            next = next.intersection(bounds)
            guard !next.isNull else { return }
        }
        rect = next
    }

    /// 回到未开始
    public mutating func reset() {
        phase = .idle
        rect = .zero
        adjustHandle = nil
    }

    // MARK: - 命中判定

    /// 命中把手 — 角优先，其次边，最后内部移动；未成立时返回 nil
    ///
    /// 选区太小时绘制层不画锚点（`SelectionGeometry.shouldShowHandles`），
    /// 命中判定必须读同一个函数，否则会出现「看不见却还能拖」的把手。
    public func hitTest(_ point: CGPoint, handleSize: CGFloat) -> Handle? {
        guard phase == .selected, rect.width > 0, rect.height > 0 else { return nil }
        guard SelectionGeometry.shouldShowHandles(for: rect, handleSize: handleSize) else {
            return rect.contains(point) ? .move : nil
        }
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
