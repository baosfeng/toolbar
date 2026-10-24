// MARK: - 标注撤销栈

/// 标注集合与撤销重做栈 — 纯值类型，便于单测
public struct SnipAnnotationStack: Equatable, Sendable {

    public private(set) var annotations: [SnipAnnotation] = []
    public private(set) var redoable: [SnipAnnotation] = []

    public init() {}

    public var isEmpty: Bool { annotations.isEmpty }
    public var canUndo: Bool { !annotations.isEmpty }
    public var canRedo: Bool { !redoable.isEmpty }

    /// 新增一条标注，新操作会清空重做栈
    public mutating func add(_ annotation: SnipAnnotation) {
        annotations.append(annotation)
        redoable.removeAll()
    }

    /// 撤销最后一条；无内容时无操作
    public mutating func undo() {
        guard let last = annotations.popLast() else { return }
        redoable.append(last)
    }

    /// 重做刚撤销的一条
    public mutating func redo() {
        guard let last = redoable.popLast() else { return }
        annotations.append(last)
    }

    /// 清空全部（不可撤销）
    public mutating func clear() {
        annotations.removeAll()
        redoable.removeAll()
    }

    /// 移除某一条（橡皮擦按整条删除时使用）
    public mutating func remove(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        annotations.remove(at: index)
        redoable.removeAll()
    }

    /// 原地替换某一条（局部擦除后回写）
    public mutating func replace(at index: Int, with annotation: SnipAnnotation) {
        guard annotations.indices.contains(index) else { return }
        annotations[index] = annotation
        redoable.removeAll()
    }
}
