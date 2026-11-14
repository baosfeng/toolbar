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
    /// 是否可点击（决定无障碍角色与鼠标悬停高亮）
    public var isActionable: Bool

    public init(title: String,
                value: String,
                progress: Double? = nil,
                tone: Tone = .normal,
                isActionable: Bool = false) {
        self.title = title
        self.value = value
        self.progress = progress
        self.tone = tone
        self.isActionable = isActionable
    }
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
    public static func metrics(rowWidth: CGFloat,
                               leadingInset: CGFloat,
                               trailingInset: CGFloat,
                               titleWidth: CGFloat,
                               valueWidth: CGFloat,
                               gap: CGFloat,
                               hasProgress: Bool,
                               minBarWidth: CGFloat) -> Metrics {
        let content = max(rowWidth - leadingInset - trailingInset, 0)
        // 数值优先：它最不该被截断
        let value = min(valueWidth, content)
        let afterValue = max(content - value - gap, 0)
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
