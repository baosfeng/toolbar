import CoreGraphics

// MARK: - 面板分段几何（纯逻辑）

/// 剪贴板面板的分段几何 —— 纯算术，不含 AppKit，供面板视图与 TestRunner 共用
///
/// 自上而下四段（翻转坐标，y 向下）：工具条 → 卡片区（弹性）→ 详情区（常驻）→ 提示行。
/// 详情区高度恒定、只由本类型给出，与「有没有选中」「正文多长」无关，
/// 因此选中项切换时整块面板不会跳动；面板高度变化只作用于卡片区。
public enum ClipboardPanelLayout {

    /// 工具条高度
    public static let toolbarHeight: CGFloat = 32
    /// 板标签行高度（在工具条之下、卡片区之上；高度从卡片区弹性格借）
    public static let boardRowHeight: CGFloat = 26
    /// 底部提示行高度
    public static let footerHeight: CGFloat = 24
    /// 左右内边距
    public static let paddingX: CGFloat = 10
    /// 卡片高度（与 `ClipboardCardGeometry` 的卡片尺寸同口径，卡片区至少容得下整卡）
    public static let cardHeight: CGFloat = 198
    /// 卡片区在整卡之外预留的上下留白
    public static let cardSlack: CGFloat = 6
    /// 工具条控件高（搜索框 / 过滤 / 按钮同一档）
    public static let toolbarControlHeight: CGFloat = 24
    /// 工具条与提示行的控件间距
    public static let toolbarGap: CGFloat = 8
    /// 搜索框宽度范围
    public static let searchMinWidth: CGFloat = 300
    public static let searchMaxWidth: CGFloat = 420
    /// 「?」快捷键帮助按钮定宽（纯图标）
    public static let helpButtonWidth: CGFloat = 24
    /// 提示行文案行高
    public static let footerTextHeight: CGFloat = 16

    /// 面板高度下限：卡片区刚好容下整卡（再矮就把卡片裁掉）
    public static let minPanelHeight: Double =
        Double(toolbarHeight + boardRowHeight + cardHeight + cardSlack
               + ClipboardDetailStrip.totalHeight + footerHeight)
    /// 面板默认高度
    public static let defaultPanelHeight: Double = minPanelHeight
    /// 面板高度上限（设置页高度滑块同口径）
    public static let maxPanelHeight: Double = 480

    /// 四段矩形（翻转坐标，y 向下）
    public struct Sections: Equatable, Sendable {
        /// 工具条
        public let toolbar: CGRect
        /// 板标签行（全部 / 各板 / ＋新建）
        public let boardRow: CGRect
        /// 卡片区（弹性；卡片在此区内垂直居中）
        public let cards: CGRect
        /// 详情区（含顶部的 1pt 分隔线）
        public let detail: CGRect
        /// 底部提示行
        public let footer: CGRect

        /// 面板层分隔线的纵坐标：工具条底 / 提示行顶
        ///
        /// 详情区顶那条线由详情区自己画（它是详情区高度里的 1pt），这里不重复列。
        public var separatorYs: [CGFloat] { [toolbar.maxY, footer.minY] }
    }

    /// 按面板尺寸切四段
    ///
    /// 只有卡片区左右内缩；工具条、详情区、提示行都用整宽——详情区那条分隔线要横贯面板，
    /// 两边都内缩会让它看起来像一条短横杠。各段内部的内边距由各自视图负责，
    /// 这里只管纵向分段与卡片区的左右让位。
    public static func sections(in size: CGSize) -> Sections {
        let fullWidth = max(0, size.width)
        let detailHeight = ClipboardDetailStrip.totalHeight
        let boardY = toolbarHeight
        let cardsY = boardY + boardRowHeight
        let cardsHeight = max(0, size.height - cardsY - detailHeight - footerHeight)
        let detailY = max(cardsY, size.height - footerHeight - detailHeight)
        return Sections(
            toolbar: CGRect(x: 0, y: 0, width: fullWidth, height: toolbarHeight),
            boardRow: CGRect(x: 0, y: boardY, width: fullWidth, height: boardRowHeight),
            cards: CGRect(x: paddingX, y: cardsY,
                          width: max(0, fullWidth - paddingX * 2), height: cardsHeight),
            detail: CGRect(x: 0, y: detailY, width: fullWidth, height: detailHeight),
            footer: CGRect(x: 0, y: max(detailY, size.height - footerHeight),
                           width: fullWidth, height: footerHeight))
    }

    /// 夹紧面板高度：低于下限（卡片被裁）或高于上限（设置页滑块范围）都拉回边界
    public static func clampedHeight(_ preferred: Double) -> Double {
        guard preferred.isFinite, preferred > 0 else { return defaultPanelHeight }
        return min(max(preferred, minPanelHeight), maxPanelHeight)
    }
}
// MARK: - 工具条与提示行的列宽分配

/// 工具条与提示行的横向分配 —— 纯算术，视图只做 frame 赋值
///
/// 两个都是「一段定宽 + 一段弹性 + 右对齐一段」的老问题，写在视图里既测不到、
/// 也容易在改动一处宽度时把另一处的间距算错（间距数量必须与控件数量对上）。
extension ClipboardPanelLayout {

    /// 工具条内部的控件尺寸
    public struct ToolbarMetrics: Equatable, Sendable {
        /// 筛选芯片行（含「＋筛选」按钮；芯片多时收进「+N」徽标）
        public let chipRow: ClipboardFilterChipRow.Metrics
        /// 搜索框（弹性，紧接在芯片行右侧）
        public let search: CGRect
        /// 「采集当前剪贴板」
        public let capture: CGRect
        /// 「?」快捷键帮助（纯图标按钮）
        public let help: CGRect

        public init(chipRow: ClipboardFilterChipRow.Metrics, search: CGRect,
                    capture: CGRect, help: CGRect) {
            self.chipRow = chipRow
            self.search = search
            self.capture = capture
            self.help = help
        }
    }

    /// 工具条：芯片行 +「＋筛选」在左，搜索框弹性紧跟其右，采集贴右边缘，「?」在采集左侧
    ///
    /// 芯片行是有界的：最多占可用宽的 45%，且必须给搜索框留下限宽度 —— 所以芯片一多就收进
    /// 「+N」徽标而不是压缩搜索框，也不会盖住「＋筛选」按钮（那是回到「全部已选」的唯一入口）。
    /// 窄到容不下「下限搜索框 + 按钮」时，芯片行让位、按钮仍贴左内侧，搜索框按剩余宽给（不溢出面板）。
    ///
    /// - Parameters:
    ///   - width: 面板宽
    ///   - captureWidth: 采集按钮实测宽（文案由 AppKit 量，这里不猜）
    ///   - chips: 已选芯片（宽度由视图按字体实测后传入；空数组表示没有筛选）
    public static func toolbarMetrics(width: CGFloat, captureWidth: CGFloat,
                                      chips: [ClipboardFilterChipRow.Chip] = []) -> ToolbarMetrics {
        let controlY = (toolbarHeight - toolbarControlHeight) / 2
        let chipY = (toolbarHeight - ClipboardFilterChipRow.chipHeight) / 2
        let captureWidth = max(96, captureWidth)
        let capture = CGRect(x: width - paddingX - captureWidth, y: controlY,
                             width: captureWidth, height: toolbarControlHeight)
        let help = CGRect(x: capture.minX - toolbarGap - helpButtonWidth, y: controlY,
                          width: helpButtonWidth, height: toolbarControlHeight)

        let lane = max(0, help.minX - toolbarGap - paddingX)
        let chipRow = ClipboardFilterChipRow.layout(
            chips: chips, originX: paddingX, y: chipY,
            available: chipBudget(lane: lane))
        let searchX = chipRow.isVisible
            ? chipRow.rightEdge + ClipboardFilterChipRow.searchGap
            : paddingX
        let search = CGRect(x: searchX, y: controlY,
                            width: max(0, min(searchMaxWidth, help.minX - toolbarGap - searchX)),
                            height: toolbarControlHeight)
        return ToolbarMetrics(chipRow: chipRow, search: search, capture: capture, help: help)
    }

    /// 芯片行可用的横向预算
    ///
    /// 先保住搜索框的下限宽，剩下的才轮到芯片行；连「筛选按钮 + 一个省略徽标」都放不下时
    /// 一位都不给（整行让位）——宁可这一档没有筛选入口，也不把搜索框压到下限以下。
    private static func chipBudget(lane: CGFloat) -> CGFloat {
        let spare = lane - searchMinWidth - ClipboardFilterChipRow.searchGap
        let floor = ClipboardFilterChipRow.menuButtonWidth + ClipboardFilterChipRow.overflowWidth
            + ClipboardFilterChipRow.chipGap * 2
        guard spare >= floor else { return 0 }
        return min(lane * ClipboardFilterChipRow.maxWidthRatio, spare)
    }

    /// 提示行的各段横向位置
    public struct FooterMetrics: Equatable, Sendable {
        /// 件数计数
        public let count: CGRect
        /// 栈进度（紧凑布局里宽度为 0，即让位）
        public let stack: CGRect
        /// 按键提示
        public let hint: CGRect
        /// 辅助功能权限入口（贴右边缘）
        public let permission: CGRect

        public init(count: CGRect, stack: CGRect, hint: CGRect, permission: CGRect) {
            self.count = count
            self.stack = stack
            self.hint = hint
            self.permission = permission
        }
    }

    /// 提示行：计数 → 栈进度 → 按键提示（弹性，右对齐），最右是权限入口
    ///
    /// 宽度不足时优先让栈进度退出（栈状态仍由卡片角标与面板提示兜底），
    /// 计数与提示共享剩余空间 —— 窄面板下计数不会先消失。
    ///
    /// - Parameters:
    ///   - width: 面板宽
    ///   - height: 面板高（提示行贴底）
    ///   - countWidth: 计数的实测宽（隐藏时传 0）
    ///   - stackWidth: 栈进度的实测宽（隐藏时传 0）
    ///   - permissionWidth: 权限入口的实测宽
    public static func footerMetrics(width: CGFloat, height: CGFloat,
                                     countWidth rawCountWidth: CGFloat,
                                     stackWidth rawStackWidth: CGFloat,
                                     permissionWidth rawPermissionWidth: CGFloat) -> FooterMetrics {
        let textY = height - footerHeight + (footerHeight - footerTextHeight) / 2
        let permissionWidth = max(72, rawPermissionWidth)
        let permission = CGRect(x: width - paddingX - permissionWidth, y: textY,
                                width: permissionWidth, height: footerTextHeight)
        let countWidth = rawCountWidth > 0 ? min(160, rawCountWidth) : 0
        let stackWidth = rawStackWidth > 0 ? min(120, rawStackWidth) : 0
        let hintRight = permission.minX - toolbarGap
        let countX = paddingX
        let stackX = countX + (countWidth > 0 ? countWidth + toolbarGap : 0)
        let hintX = stackX + (stackWidth > 0 ? stackWidth + toolbarGap : 0)

        let count = CGRect(x: countX, y: textY, width: countWidth, height: footerTextHeight)
        guard hintX < hintRight else {
            // 紧凑布局：栈进度让位，提示从计数右边缘起铺到权限入口之前
            return FooterMetrics(count: count,
                                 stack: CGRect(x: stackX, y: textY, width: 0, height: footerTextHeight),
                                 hint: CGRect(x: stackX, y: textY,
                                              width: max(0, hintRight - stackX), height: footerTextHeight),
                                 permission: permission)
        }
        return FooterMetrics(count: count,
                             stack: CGRect(x: stackX, y: textY, width: stackWidth, height: footerTextHeight),
                             hint: CGRect(x: hintX, y: textY,
                                          width: max(0, hintRight - hintX), height: footerTextHeight),
                             permission: permission)
    }
}
