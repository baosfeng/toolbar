import Foundation

// MARK: - 多选变换口径（纯逻辑）

/// 卡片多选状态机 —— 只放「集合 + 焦点」的变换规则，视图与控制器只调这里
///
/// 三种点击语义与 macOS 列表一致：无修饰键 = 替换为单条；⌘ = 切换该条；⇧ = 从焦点扩展到该条。
/// 不变式：`ids` 恒为可见条目子集，`focusedID` 要么是 `ids` 成员，要么在 `ids` 为空时为 nil。
/// 焦点就是方向键与详情区的落点，因此单条选中态可以从它派生，不必另存下标。
public struct ClipboardSelectionModel: Equatable, Sendable {

    /// 点击语义（由卡片交互层的修饰键换算而来）
    public enum Click: Sendable {
        /// 无修饰键：替换选中为这一条
        case replace
        /// ⌘：切换这一条的选中态
        case toggle
        /// ⇧：从当前焦点扩展到这一条
        case extend
    }

    /// 选中集合
    public private(set) var ids: Set<UUID>
    /// 焦点条目（方向键与详情区的落点）
    public private(set) var focusedID: UUID?

    public init(ids: Set<UUID> = [], focusedID: UUID? = nil) {
        self.ids = ids
        self.focusedID = focusedID
    }

    /// 选中条数
    public var count: Int { ids.count }

    /// 是否处于多选态（条数 > 1 才需要「已选 N 条」与隐藏 ⌘N 角标）
    public var isMultiSelecting: Bool { ids.count > 1 }

    /// 按集合顺序取选中项（用于批量删除后的提示文案）
    public func orderedIDs(in visibleIDs: [UUID]) -> [UUID] {
        visibleIDs.filter { ids.contains($0) }
    }

    // MARK: 变换

    /// 一次点击：按语义改集合与焦点
    ///
    /// - Parameters:
    ///   - id: 被点击的条目
    ///   - click: 点击语义
    ///   - visibleIDs: 当前过滤后的可见条目（⇧ 范围选与裁剪都以此为准）
    public mutating func click(_ id: UUID, click: Click, visibleIDs: [UUID]) {
        guard visibleIDs.contains(id) else { return }
        switch click {
        case .replace:
            ids = [id]
            focusedID = id
        case .toggle:
            if ids.contains(id) {
                ids.remove(id)
                // 取消掉的正是焦点时，焦点回落到剩余选中项（仍可按方向键继续走）
                if focusedID == id { focusedID = ids.isEmpty ? nil : orderedIDs(in: visibleIDs).first }
            } else {
                ids.insert(id)
                focusedID = id
            }
        case .extend:
            // 没有焦点（或焦点已不可见）时退化为替换，保证 ⇧ 单击总能选中目标
            guard let anchor = focusedID,
                  let from = visibleIDs.firstIndex(of: anchor),
                  let to = visibleIDs.firstIndex(of: id) else {
                ids = [id]
                focusedID = id
                return
            }
            let range = min(from, to)...max(from, to)
            ids = Set(visibleIDs[range])
            focusedID = anchor   // 范围选的锚点保持不变，连续 ⇧ 点击才能来回扩缩
        }
    }

    /// 全选当前可见条目（焦点落到第一条）
    public mutating func selectAll(visibleIDs: [UUID]) {
        guard !visibleIDs.isEmpty else { return }
        ids = Set(visibleIDs)
        focusedID = visibleIDs.first
    }

    /// 清空选中（Esc / 收起面板 / 进入编辑态）
    public mutating func clear() {
        ids.removeAll()
        focusedID = nil
    }

    /// 方向键移动：焦点换成这一条，选中同时替换为单条
    public mutating func focus(_ id: UUID?) {
        guard let id else { clear(); return }
        ids = [id]
        focusedID = id
    }

    /// 过滤 / 重载后裁剪：丢掉不再可见的选中项，焦点回落到第一条存活项
    public mutating func prune(visibleIDs: [UUID]) {
        guard !visibleIDs.isEmpty else { clear(); return }
        ids.formIntersection(visibleIDs)
        if let focused = focusedID, visibleIDs.contains(focused) {
            // 焦点仍可见：只补一条不变式（焦点必在集合内）
            if ids.isEmpty { ids = [focused] }
            return
        }
        let surviving = orderedIDs(in: visibleIDs)
        if let first = surviving.first {
            focusedID = first
        } else {
            // 一条都不剩：把焦点落到可见首条并单选中它，避免详情区悬空
            focusedID = visibleIDs.first
            ids = Set(visibleIDs.prefix(1))
        }
    }
}
