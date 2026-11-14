import Foundation

// MARK: - 自绘列表的行规格与其宽度分配

/// 一行自绘列表的数据规格
///
/// 纯数据、可比较：不含 AppKit 类型，也不含闭包（点击统一由列表的 `onRowAction(index)` 回调），
/// 因此 TestRunner 可以直接断言，视图侧只负责把它画出来。
public struct DrawnRowSpec: Equatable {
    /// 数值的语气（决定数值颜色）
    public enum Tone: Equatable {
        /// 常规（次要文字色）
        case normal
        /// 强调（主文字色 + 粗体）
        case strong
        /// 告警（警示色）
        case warning
    }

    /// 行名（左侧）
    public var title: String
    /// 行值（右侧，等宽数字）
    public var value: String
    /// 进度条（0…1；nil = 不画进度，名称与数值之间直接留空）
    public var progress: Double?
    /// 数值语气
    public var tone: Tone
    /// 是否画「空描边条」（不可得态的占位条：只有轮廓、没有填充）
    public var isEmptyBar: Bool
    /// 是否可点击（决定无障碍角色与鼠标悬停高亮）
    public var isActionable: Bool
    /// 第二行副文本（空串 = 单行式行；非空时这一行按两行式排，进度条改画整行底部）
    public var detail: String
    /// 右侧第二列（如占比；空串 = 不画；画在行值右边、贴最右）
    public var secondary: String
    /// 是否在行前画 6pt 色点（排行行的「与占比条同色」标记）
    public var showsSwatch: Bool

    public init(title: String,
                value: String,
                progress: Double? = nil,
                tone: Tone = .normal,
                isActionable: Bool = false,
                isEmptyBar: Bool = false,
                detail: String = "",
                secondary: String = "",
                showsSwatch: Bool = false) {
        self.title = title
        self.value = value
        self.progress = progress
        self.tone = tone
        self.isActionable = isActionable
        self.isEmptyBar = isEmptyBar
        self.detail = detail
        self.secondary = secondary
        self.showsSwatch = showsSwatch
    }

    /// 是否两行式（有副文本）
    public var isStacked: Bool { !detail.isEmpty }
}

// MARK: - 宽度分配（纯计算）

/// 自绘行的宽度分配规则
///
/// 顺序固定为「行名 → 进度条（可选）→ 数值」，数值贴右。
/// 当行名吃掉大部分宽度、留给进度条的不足 `minBarWidth` 时，**宁可整条进度不画**
/// 也不画一条细到看不清的线（这是与现有 AppKit 行一致的取舍）。
public enum DrawnRowLayout {

    /// 一行的最终几何
    public struct Metrics: Equatable {
        /// 行名可用宽度
        public let titleWidth: CGFloat
        /// 数值实测宽度（已按可用宽度截断）
        public let valueWidth: CGFloat
        /// 进度条宽度（0 = 不画）
        public let barWidth: CGFloat
        /// 是否绘制进度条
        public var showsBar: Bool { barWidth > 0 }

        public init(titleWidth: CGFloat, valueWidth: CGFloat, barWidth: CGFloat) {
            self.titleWidth = max(titleWidth, 0)
            self.valueWidth = max(valueWidth, 0)
            self.barWidth = max(barWidth, 0)
        }
    }

    /// 计算一行的宽度分配
    /// - Parameters:
    ///   - rowWidth: 行总宽
    ///   - leadingInset: 左侧内边距
    ///   - trailingInset: 右侧内边距
    ///   - titleWidth: 行名实测宽度（未截断）
    ///   - valueWidth: 数值实测宽度（未截断）
    ///   - gap: 名称 / 进度条 / 数值之间的最小间距
    ///   - hasProgress: 这一行是否有进度条
    ///   - minBarWidth: 进度条可画的最小宽度，低于它就不画
    ///   - leadingWidth: 行名左侧固定占用宽度（如进程图标列；0 = 无），
    ///     它之后再吃掉一个 `gap` 作为与行名的间距
    public static func metrics(rowWidth: CGFloat,
                               leadingInset: CGFloat,
                               trailingInset: CGFloat,
                               titleWidth: CGFloat,
                               valueWidth: CGFloat,
                               gap: CGFloat,
                               hasProgress: Bool,
                               minBarWidth: CGFloat,
                               leadingWidth: CGFloat = 0) -> Metrics {
        let content = max(rowWidth - leadingInset - trailingInset, 0)
        // 左侧附加块（图标列）挤出的宽度：图标列 + 它后面的一个间距
        // 图标列再宽也不超过内容宽——否则整行会被挤成负宽度
        let leading = leadingWidth > 0 ? min(leadingWidth + gap, content) : 0
        let available = max(content - leading, 0)
        // 数值优先：它最不该被截断
        let value = min(valueWidth, available)
        let afterValue = max(available - value - gap, 0)
        guard afterValue > 0 else {
            return Metrics(titleWidth: 0, valueWidth: value, barWidth: 0)
        }
        guard hasProgress else {
            return Metrics(titleWidth: min(titleWidth, afterValue), valueWidth: value, barWidth: 0)
        }
        // 行名优先：按实测宽度占位（不够就截断到可用宽度），剩余才给进度条
        let title = min(titleWidth, afterValue)
        let bar = afterValue - title - gap
        // 剩余不够画一条看得清的进度条就不画——长标题行宁可没有进度条，
        // 也不要一条挤在文字后面的小色块
        guard bar >= minBarWidth else {
            return Metrics(titleWidth: title, valueWidth: value, barWidth: 0)
        }
        return Metrics(titleWidth: title, valueWidth: value, barWidth: bar)
    }

    /// 列表内容总高（N 行 + 行间空隙，最后一行后不留空）
    public static func contentHeight(rowCount: Int, rowHeight: CGFloat, rowSpacing: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}
