import CoreGraphics
import Foundation

// MARK: - 板标签行几何（纯逻辑）

/// 板标签行的排版 —— 纯算术，不含 AppKit，视图只做 frame 赋值
///
/// 一行三样东西：「全部」+ 各板（色点 + 名称）+ 右侧「＋」新建。放不下时不换行、不压缩单枚标签，
/// 把放不下的收进「+N」徽标 —— 「全部」永远排在最左，不会被挤掉。
public enum ClipboardBoardRow {

    /// 行高：与面板分段同源（ClipboardPanelLayout.boardRowHeight），不另立第二份字面量
    public static var rowHeight: CGFloat { ClipboardPanelLayout.boardRowHeight }
    /// 标签胶囊高
    public static let chipHeight: CGFloat = 20
    /// 标签左右内边距
    public static let chipPaddingX: CGFloat = 8
    /// 标签之间的间距
    public static let chipGap: CGFloat = 6
    /// 色点直径
    public static let dotSize: CGFloat = 6
    /// 色点与文字的间距
    public static let dotGap: CGFloat = 5
    /// 「＋」新建按钮宽
    public static let addButtonWidth: CGFloat = 24
    /// 「+N」徽标宽
    public static let overflowWidth: CGFloat = 28
    /// 「全部」标签的固定标识（其余标签用板的 uuid 字符串）
    public static let allChipID = "all"

    /// 一枚待排标签：文案只用于绘制，宽度由调用方按字体实测后传入
    public struct Chip: Equatable, Sendable {
        /// 稳定标识：「全部」用 all，其余是板的 uuid 字符串
        public let id: String
        /// 标签文案
        public let label: String
        /// 色板下标（nil = 「全部」，不画色点）
        public let colorIndex: Int?
        /// 实测宽（含内边距与色点占位）
        public let width: CGFloat

        public init(id: String, label: String, colorIndex: Int?, width: CGFloat) {
            self.id = id
            self.label = label
            self.colorIndex = colorIndex
            self.width = width
        }
    }

    /// 一枚已排定的标签
    public struct Placed: Equatable, Sendable {
        public let id: String
        public let label: String
        public let colorIndex: Int?
        public let frame: CGRect

        public init(id: String, label: String, colorIndex: Int?, frame: CGRect) {
            self.id = id
            self.label = label
            self.colorIndex = colorIndex
            self.frame = frame
        }
    }

    /// 标签行的排版结果
    public struct Metrics: Equatable, Sendable {
        /// 放得下的标签（按传入顺序从左排）
        public let chips: [Placed]
        /// 「+N」徽标（放得下全部标签时为 nil）
        public let overflow: Placed?
        /// 「＋」新建按钮
        public let addButton: CGRect
        /// 本行实际占到的右边缘
        public let rightEdge: CGFloat
        /// 是否有标签被收进徽标
        public var isTruncated: Bool { overflow != nil }
        /// 本档是否显示这一行（可用宽为 0 时整行让位）
        public var isVisible: Bool { addButton.width > 0 }

        public init(chips: [Placed], overflow: Placed?, addButton: CGRect, rightEdge: CGFloat) {
            self.chips = chips
            self.overflow = overflow
            self.addButton = addButton
            self.rightEdge = rightEdge
        }
    }

    /// 排标签行
    ///
    /// 不变量：rightEdge − originX ≤ available（永不溢出可用宽），且「＋」按钮优先于标签占位
    /// —— 新建是这一行唯一的写入口，标签可以省略，它必须还在。
    ///
    /// - Parameters:
    ///   - chips: 待排标签（宽度已实测，第一枚应是「全部」）
    ///   - originX: 行起点（面板左内边距）
    ///   - rowY: 行顶（标签在行内垂直居中）
    ///   - available: 本行可用宽
    public static func layout(chips: [Chip], originX: CGFloat, rowY: CGFloat,
                              available: CGFloat) -> Metrics {
        let wide = max(0, available)
        guard wide > 0 else {
            return Metrics(chips: [], overflow: nil, addButton: .zero, rightEdge: originX)
        }
        let chipY = rowY + (rowHeight - chipHeight) / 2
        let addButton = CGRect(x: originX + wide - addButtonWidth, y: chipY,
                               width: addButtonWidth, height: chipHeight)
        // 标签只用扣掉按钮与一个间距后的宽：按钮贴右，绝不因标签多而消失
        let chipsSpace = max(0, wide - addButtonWidth - chipGap)
        var cursor = originX
        var placed: [Placed] = []
        var dropped = 0
        for chip in chips {
            guard chip.width > 0, cursor + chip.width - originX <= chipsSpace else {
                dropped += 1
                continue
            }
            placed.append(Placed(id: chip.id, label: chip.label, colorIndex: chip.colorIndex,
                                 frame: CGRect(x: cursor, y: chipY, width: chip.width, height: chipHeight)))
            cursor += chip.width + chipGap
        }
        // 有标签被省略就必须有「+N」：徽标放不下时撤回最后一枚给它让位（宁可少显示，不静默丢）
        while dropped > 0, cursor + overflowWidth - originX > chipsSpace, let last = placed.popLast() {
            dropped += 1
            cursor = last.frame.minX
        }
        var overflow: Placed?
        if dropped > 0, cursor + overflowWidth - originX <= chipsSpace {
            overflow = Placed(id: "overflow", label: "+\(dropped)", colorIndex: nil,
                              frame: CGRect(x: cursor, y: chipY, width: overflowWidth, height: chipHeight))
        }
        let rightEdge = max(addButton.maxX, overflow?.frame.maxX ?? originX)
        return Metrics(chips: placed, overflow: overflow, addButton: addButton, rightEdge: rightEdge)
    }

    /// 一枚标签的宽 = 色点占位（「全部」不占）+ 文字宽 + 左右内边距
    public static func chipWidth(textWidth: CGFloat, hasDot: Bool) -> CGFloat {
        max(0, ceil(textWidth)) + chipPaddingX * 2 + (hasDot ? dotSize + dotGap : 0)
    }
}

// MARK: - 板之间的循环切换（⌘← / ⌘→）

/// 板循环 —— 在「全部 + 各板」序列里前后跳，纯函数，键盘层与测试共用同一份口径
public enum ClipboardBoardCycle {

    /// 切换一位
    ///
    /// 序列恒为「全部」+ 各板（下标 0 = 全部）。越界按环回绕：最后一板再往右回到「全部」，
    /// 「全部」再往左落在最后一板 —— 与条目方向键的环回口径一致。
    /// - Parameters:
    ///   - current: 当前选中板（nil = 全部）
    ///   - boardIDs: 全部板 id（按展示顺序）
    ///   - step: +1 向后 / −1 向前
    /// - Returns: 新选中的板 id（nil = 全部）
    public static func next(current: UUID?, boardIDs: [UUID], step: Int) -> UUID? {
        let sequence: [UUID?] = [nil] + boardIDs.map { Optional($0) }
        guard sequence.count > 1, step != 0 else { return current }
        let currentIndex = sequence.firstIndex { $0 == current } ?? 0
        let count = sequence.count
        let raw = currentIndex + (step > 0 ? 1 : -1)
        let nextIndex = ((raw % count) + count) % count
        return sequence[nextIndex]
    }
}

// MARK: - 按板过滤

/// 切板过滤 —— 只看两个 id，不碰仓储与 UI 状态，便于单测钉住「全部 = 不过滤」
public enum ClipboardBoardFilter {

    /// 条目是否属于当前选中板
    ///
    /// - Parameters:
    ///   - itemBoardID: 条目所属板（nil = 未归类）
    ///   - selected: 当前选中板（nil = 「全部」，不过滤）
    public static func matches(itemBoardID: UUID?, selected: UUID?) -> Bool {
        guard let selected else { return true }
        return itemBoardID == selected
    }
}
