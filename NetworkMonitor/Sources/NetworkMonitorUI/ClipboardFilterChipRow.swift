import CoreGraphics

// MARK: - 筛选芯片行几何（纯逻辑）

/// 筛选芯片行的排版 —— 纯算术，不含 AppKit，视图只做 frame 赋值
///
/// 一条链：芯片行（左，可省略）→「＋筛选」按钮 → 搜索框（弹性）。芯片多到放不下时
/// 不换行、不压缩单枚芯片宽度，而是把放不下的收进「+N」徽标（点「＋筛选」能看到全部已选）。
///
/// 为什么放渲染层不算、放纯函数算：芯片宽度由字体实测，但「放几枚、要不要徽标、搜索框还剩多少」
/// 是纯算术，写进视图既测不到，也容易在加一类芯片时把间距数量算错（间距必须与控件数对上）。
public enum ClipboardFilterChipRow {

    /// 芯片高（工具条 24pt 控件里的饱满胶囊）
    public static let chipHeight: CGFloat = 18
    /// 芯片左右内边距
    public static let chipPaddingX: CGFloat = 7
    /// 芯片之间的间距
    public static let chipGap: CGFloat = 6
    /// 芯片右侧删除叉的占位宽
    public static let removeGlyphWidth: CGFloat = 10
    /// 「+N」徽标宽
    public static let overflowWidth: CGFloat = 30
    /// 「＋筛选」按钮宽（方形图标按钮）
    public static let menuButtonWidth: CGFloat = 36
    /// 芯片行与搜索框之间的间距
    public static let searchGap: CGFloat = 6
    /// 芯片行最多占工具条可用宽的比例（剩下的留给搜索框）
    public static let maxWidthRatio: CGFloat = 0.45

    /// 一枚待排芯片：文案只用于视图绘制，宽度由调用方按字体量好传进来
    public struct Chip: Equatable, Sendable {
        /// 稳定标识（芯片 kind + value），视图据此把排好的矩形映射回原芯片
        public let id: String
        /// 芯片文案
        public let label: String
        /// 实测宽（含内边距与删除叉）
        public let width: CGFloat

        public init(id: String, label: String, width: CGFloat) {
            self.id = id
            self.label = label
            self.width = width
        }
    }

    /// 一枚已排定的芯片
    public struct Placed: Equatable, Sendable {
        /// 稳定标识（同 Chip.id）
        public let id: String
        /// 芯片文案
        public let label: String
        /// 芯片矩形
        public let frame: CGRect

        public init(id: String, label: String, frame: CGRect) {
            self.id = id
            self.label = label
            self.frame = frame
        }
    }

    /// 芯片行的排版结果
    public struct Metrics: Equatable, Sendable {
        /// 放得下的芯片（按传入顺序，从左侧起排）
        public let chips: [Placed]
        /// 「+N」徽标（放得下全部芯片时为 nil）
        public let overflow: Placed?
        /// 「＋筛选」按钮
        public let menuButton: CGRect
        /// 芯片行（含按钮）实际占到的右边缘；没有芯片时等于按钮右边缘
        public let rightEdge: CGFloat
        /// 是否有芯片被收进徽标
        public var isTruncated: Bool { overflow != nil }

        /// 这一档是否真的显示芯片行（可用宽不足时整行让位，按钮也不出现）
        public var isVisible: Bool { menuButton.width > 0 }

        public init(chips: [Placed], overflow: Placed?, menuButton: CGRect, rightEdge: CGFloat) {
            self.chips = chips
            self.overflow = overflow
            self.menuButton = menuButton
            self.rightEdge = rightEdge
        }
    }

    /// 排芯片行
    ///
    /// 不变量：`rightEdge - originX <= available`（永不溢出可用宽），且「＋筛选」按钮优先于芯片占位
    /// —— 按钮是回到「全部已选」的唯一入口，芯片被省略时它必须还在。
    ///
    /// - Parameters:
    ///   - chips: 待排芯片（宽度已实测）
    ///   - originX: 行起点（工具条左内边距）
    ///   - y: 行顶（工具条内垂直居中后的 y）
    ///   - available: 本行可用宽（已扣掉右侧采集 / 帮助按钮与间距）
    public static func layout(chips: [Chip], originX: CGFloat, y: CGFloat, available: CGFloat) -> Metrics {
        let wide = max(0, available)
        // 可用宽为 0 表示「这一档不给芯片行留位置」：整行让位，连按钮都不出现，
        // 把宽度全留给搜索框（窄面板下宁可没有筛选入口，也不把搜索框挤到读不清）
        guard wide > 0 else {
            return Metrics(chips: [], overflow: nil, menuButton: .zero, rightEdge: originX)
        }
        let menuHeight = chipHeight
        // 按钮优先：连按钮都放不下时也贴着起点排，宁可压搜索框也不让入口消失
        let chipsSpace = max(0, wide - menuButtonWidth - chipGap)
        var cursor = originX
        var placed: [Placed] = []
        var dropped = 0
        for chip in chips {
            guard chip.width > 0, cursor + chip.width - originX <= chipsSpace else {
                dropped += 1
                continue
            }
            placed.append(Placed(id: chip.id, label: chip.label,
                                 frame: CGRect(x: cursor, y: y, width: chip.width, height: chipHeight)))
            cursor += chip.width + chipGap
        }
        // 有芯片被省略就必须有「+N」徽标：徽标放不下时撤回最后一枚芯片给它让位
        // （宁可少显示一枚芯片，也不能让被省略的芯片静默消失）
        while dropped > 0, cursor + overflowWidth - originX > chipsSpace, let last = placed.popLast() {
            dropped += 1
            cursor = last.frame.minX
        }
        var overflow: Placed?
        if dropped > 0, cursor + overflowWidth - originX <= chipsSpace {
            overflow = Placed(id: "overflow", label: "+\(dropped)",
                              frame: CGRect(x: cursor, y: y, width: overflowWidth, height: chipHeight))
            cursor += overflowWidth + chipGap
        }
        let menuX = placed.isEmpty && overflow == nil ? originX : cursor
        let menuButton = CGRect(x: menuX, y: y, width: menuButtonWidth, height: menuHeight)
        // 右边缘取按钮与最后一个芯片的较大者：芯片全被省略时按钮仍是行的实际右界
        let rightEdge = max(menuButton.maxX, overflow?.frame.maxX ?? 0)
        return Metrics(chips: placed, overflow: overflow, menuButton: menuButton, rightEdge: rightEdge)
    }
}
