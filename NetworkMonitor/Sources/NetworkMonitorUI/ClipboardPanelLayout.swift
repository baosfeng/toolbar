import CoreGraphics

// MARK: - 面板分段几何（纯逻辑）

/// 剪贴板面板的分段几何 —— 纯算术，不含 AppKit，供面板视图与 TestRunner 共用
///
/// 自上而下只有两段（翻转坐标，y 向下）：**工具条 → 卡片区（弹性）**。
///
/// 与改造前的四段（工具条 / 板标签行 / 卡片区 / 详情区 / 提示行）相比，板标签并进工具条、
/// 详情区退成「按需浮层」（空格预览 + 编辑态），提示行走面板底部的临时状态胶囊（不占布局高度）。
/// 结果是面板高度全部给内容：高度只影响卡片尺寸，不改变单行横向布局。
public enum ClipboardPanelLayout {

    /// 工具条高度（搜索 + 板胶囊 + 计数 +「?」+ 采集图标同一行）
    public static let toolbarHeight: CGFloat = 34
    /// 左右内边距
    public static let paddingX: CGFloat = 10
    /// 卡片尺寸与面板几何同源（设计基准卡高 / 宽高比 / 卡片区留白）
    public static var cardHeight: CGFloat { ClipboardCardGeometry.baseCardHeight }
    /// 卡片区在整卡之外的上下留白合计
    public static var cardSlack: CGFloat { ClipboardCardGeometry.cardSlack }
    /// 工具条控件高（搜索框 / 图标按钮同一档）
    public static let toolbarControlHeight: CGFloat = 24
    /// 工具条控件间距
    public static let toolbarGap: CGFloat = 8
    /// 图标按钮定宽（「?」与「采集当前剪贴板」同档，纯图标 + tooltip）
    public static let iconButtonWidth: CGFloat = 24
    /// 两个图标按钮之间的窄间距（比控件间距更紧，视觉上成组）
    public static let iconGap: CGFloat = 6
    /// 搜索框宽度范围（弹性；面板多宽都不让搜索框吃掉板标签的位置）
    public static let searchMinWidth: CGFloat = 200
    public static let searchMaxWidth: CGFloat = 360
    /// 条数计数最大宽（超出的部分尾部省略）
    public static let countMaxWidth: CGFloat = 96

    /// 面板高度下限：卡片区刚好容下「最矮的整卡」（再矮就把卡片裁掉）
    ///
    /// 用 `minCardHeight`（150）而不是基准卡高（198）：下限的意义是「卡片不被裁」，
    /// 拿基准卡高当下限会把紧凑档锁死在 264，多出来那 48pt 全是没用上的高度。
    public static var minPanelHeight: Double {
        Double(toolbarHeight + ClipboardCardGeometry.minCardHeight + cardSlack)
    }
    /// 面板默认高度：标准档（卡片按 1.15 比例长到 254pt 上下，一屏约 5 张）
    ///
    /// 与 `ClipboardPanelSize.standard.height` 同源：档位按钮、设置页滑块与默认值三处
    /// 读同一个数，不会出现「点一次档位按钮，高度反而变成另一个值」。
    public static var defaultPanelHeight: Double { ClipboardPanelSize.standard.height }
    /// 面板高度上限（设置页高度滑块同口径）
    ///
    /// 不是随便取的值：卡片宽度封顶 320 后高度停在同一比例上（320 / 1.146 ≈ 279），
    /// 再高的面板只会把「卡片下沿到面板下沿」那段空白越拉越长（480 时留白 135pt）。
    /// 360 = 工具条 34 + 卡片 279 + 上下留白 47，再往上加已经没有可长的东西了。
    public static let maxPanelHeight: Double = 360

    /// 两段矩形（翻转坐标，y 向下）
    public struct Sections: Equatable, Sendable {
        /// 工具条
        public let toolbar: CGRect
        /// 卡片区（弹性；卡片在此区内按高度自适应尺寸）
        public let cards: CGRect

        /// 面板层的发丝分隔线纵坐标：只剩工具条底这一条
        public var separatorYs: [CGFloat] { [toolbar.maxY] }
    }

    /// 按面板尺寸切两段
    ///
    /// 只有卡片区左右内缩；工具条用整宽（它内部自己留内边距），
    /// 这样分隔线横贯面板、与卡片区的左右留白不互相牵连。
    public static func sections(in size: CGSize) -> Sections {
        let fullWidth = max(0, size.width)
        return Sections(
            toolbar: CGRect(x: 0, y: 0, width: fullWidth, height: toolbarHeight),
            cards: CGRect(x: paddingX, y: toolbarHeight,
                          width: max(0, fullWidth - paddingX * 2),
                          height: max(0, size.height - toolbarHeight)))
    }

    /// 夹紧面板高度：低于下限（卡片被裁）或高于上限（设置页滑块范围）都拉回边界
    public static func clampedHeight(_ preferred: Double) -> Double {
        guard preferred.isFinite, preferred > 0 else { return defaultPanelHeight }
        return min(max(preferred, minPanelHeight), maxPanelHeight)
    }
}

// MARK: - 工具条的列宽分配

/// 工具条的横向分配 —— 纯算术，视图只做 frame 赋值
///
/// 一行五段：筛选芯片行（左，可省略）→ 搜索框（弹性）→ 板胶囊（弹性收进「+N」）→ 条数计数 →
/// 「?」→ 采集图标（两个图标贴右边缘，成组）。
///
/// 为什么仍然保留筛选芯片行：类型 / 来源 / 日期筛选是既有能力（Tab / ⇧Tab 与鼠标都走它），
/// 只是把「＋筛选」收进左侧的同一行，不再单独占一行。芯片多时收进「+N」徽标，
/// 搜索框与板标签各自有下限，谁也不会被挤到读不清。
extension ClipboardPanelLayout {

    /// 工具条内部的控件尺寸
    public struct ToolbarMetrics: Equatable, Sendable {
        /// 筛选芯片行（含「＋筛选」按钮）
        public let chipRow: ClipboardFilterChipRow.Metrics
        /// 搜索框（弹性）
        public let search: CGRect
        /// 板胶囊行（全部 / 各板 / ＋新建）
        public let boardRow: ClipboardBoardRow.Metrics
        /// 条数计数（隐藏时宽度为 0）
        public let count: CGRect
        /// 「?」快捷键帮助（纯图标按钮）
        public let help: CGRect
        /// 面板高度档位（紧凑 / 标准 / 宽松；图标随档位换，点按循环）
        public let size: CGRect
        /// 「采集当前剪贴板」（纯图标按钮 + tooltip）
        public let capture: CGRect

        public init(chipRow: ClipboardFilterChipRow.Metrics, search: CGRect,
                    boardRow: ClipboardBoardRow.Metrics, count: CGRect,
                    help: CGRect, size: CGRect, capture: CGRect) {
            self.chipRow = chipRow
            self.search = search
            self.boardRow = boardRow
            self.count = count
            self.help = help
            self.size = size
            self.capture = capture
        }
    }

    /// 工具条：芯片行贴左 → 搜索框 → 板胶囊 → 计数 →「?」→ 高度档位 → 采集（后三者贴右）
    ///
    /// - Parameters:
    ///   - width: 面板宽
    ///   - countWidth: 条数计数的实测宽（隐藏时传 0）
    ///   - chips: 已选筛选芯片（宽度由视图按字体实测后传入）
    ///   - boardChips: 板胶囊（第一枚恒为「全部」，宽度已实测）
    public static func toolbarMetrics(width: CGFloat,
                                      countWidth rawCountWidth: CGFloat,
                                      chips: [ClipboardFilterChipRow.Chip] = [],
                                      boardChips: [ClipboardBoardRow.Chip] = []) -> ToolbarMetrics {
        let controlY = (toolbarHeight - toolbarControlHeight) / 2
        let capture = CGRect(x: max(0, width - paddingX - iconButtonWidth), y: controlY,
                             width: iconButtonWidth, height: toolbarControlHeight)
        // 三个图标按钮贴右成组：高度档位夹在「?」与采集之间（采集是动作、档位与「?」是面板级开关）
        let size = CGRect(x: capture.minX - iconGap - iconButtonWidth, y: controlY,
                          width: iconButtonWidth, height: toolbarControlHeight)
        let help = CGRect(x: size.minX - iconGap - iconButtonWidth, y: controlY,
                          width: iconButtonWidth, height: toolbarControlHeight)

        // 计数：贴「?」左侧，超宽尾部省略；面板太窄时整段让位（计数是状态，不是入口）
        let countWidth = rawCountWidth > 0 ? min(countMaxWidth, ceil(rawCountWidth)) : 0
        let count = countWidth > 0
            ? CGRect(x: help.minX - toolbarGap - countWidth, y: controlY,
                     width: countWidth, height: toolbarControlHeight)
            : CGRect(x: help.minX - toolbarGap, y: controlY, width: 0, height: toolbarControlHeight)
        let laneEnd = max(paddingX, (countWidth > 0 ? count.minX : help.minX) - toolbarGap)
        let lane = max(0, laneEnd - paddingX)

        let chipY = (toolbarHeight - ClipboardFilterChipRow.chipHeight) / 2
        let chipRow = ClipboardFilterChipRow.layout(chips: chips, originX: paddingX, y: chipY,
                                                    available: chipBudget(lane: lane))
        let searchX = chipRow.isVisible
            ? chipRow.rightEdge + ClipboardFilterChipRow.searchGap
            : paddingX
        // 搜索框：给板标签留出「全部 + ＋」的下限，剩下的按上限取；放不下就按剩余宽给
        let boardsMin = boardsMinWidth(chips: boardChips)
        let searchWidth = min(searchMaxWidth,
                              max(searchMinWidth, laneEnd - searchX - boardsMin - toolbarGap))
        let search = CGRect(x: searchX, y: controlY,
                            width: max(0, min(searchWidth, laneEnd - searchX)),
                            height: toolbarControlHeight)

        let boardX = search.maxX + toolbarGap
        let boardRow = ClipboardBoardRow.layout(
            chips: boardChips, originX: boardX, rowY: 0,
            available: max(0, laneEnd - boardX), rowHeight: toolbarHeight)
        return ToolbarMetrics(chipRow: chipRow, search: search, boardRow: boardRow,
                              count: count, help: help, size: size, capture: capture)
    }

    /// 筛选芯片行可用的横向预算
    ///
    /// 先保住搜索框的下限宽与板标签下限，剩下的才轮到芯片行；连「筛选按钮 + 一个省略徽标」
    /// 都放不下时一位都不给（整行让位）——宁可这一档没有筛选入口，也不把搜索框压到下限以下。
    private static func chipBudget(lane: CGFloat) -> CGFloat {
        let spare = lane - searchMinWidth - boardsFloor - ClipboardFilterChipRow.searchGap
        let floor = ClipboardFilterChipRow.menuButtonWidth + ClipboardFilterChipRow.overflowWidth
            + ClipboardFilterChipRow.chipGap * 2
        guard spare >= floor else { return 0 }
        return min(lane * ClipboardFilterChipRow.maxWidthRatio, spare)
    }

    /// 板标签的最小占位（「全部」一枚 + 间距 +「＋」新建）
    private static var boardsFloor: CGFloat { 48 + ClipboardBoardRow.addButtonWidth + ClipboardBoardRow.chipGap }

    /// 按实测宽度算板标签的最小占位（取不到「全部」时用 48pt 兜底）
    private static func boardsMinWidth(chips: [ClipboardBoardRow.Chip]) -> CGFloat {
        (chips.first?.width ?? 48) + ClipboardBoardRow.chipGap + ClipboardBoardRow.addButtonWidth
    }
}
