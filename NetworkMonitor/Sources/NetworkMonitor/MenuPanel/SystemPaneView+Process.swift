import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 进程 Top-N 条形榜

/// 进程资源榜 — 名称 / 横向条形 / 数值，每行一条
///
/// **改用自绘组件 `DrawnRowList`**：整个榜只有 1 个视图，行不再各建
/// 「nameLabel + barTrack + valueLabel + NSStackView + 6 条约束」（原来 10 行 = 41 个视图）。
///
/// 口径不变：
/// - CPU 榜条形用**绝对 sqrt 刻度**（`sqrt(cpuPercent) × 13`，满条 = 100% = 占一个核），
///   不能改成「榜首归一化」——榜单变化会让同一个值的条长乱跳；
/// - 超量程（CPU > 100%）条形转琥珀；
/// - 不可得态画空描边条（只有轮廓、无填充）。
final class SystemProcessListView: NSView {

    /// 单行数据（已按 CPU 占用排序）
    struct Row: Equatable {
        /// 进程名（超宽截断显示，全名进 toolTip）
        let name: String
        /// 条形比例 0...1（已按榜单口径算好）
        let fraction: Double
        /// 右侧数值文本（原值，不做 clamp）
        let valueText: String
        /// 是否超量程（CPU > 100%，条形转琥珀）
        let isOver: Bool
        /// 悬停说明（含 pid 与完整口径）
        let tip: String
    }

    /// 整个榜的唯一视图
    private let list = DrawnRowList()
    /// 固定行数（不足的行按不可得态占位）
    private let capacity: Int
    private var rows: [Row] = []
    private var unavailableTip = ""

    init(rows: Int = 3) {
        capacity = max(1, rows)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        list.translatesAutoresizingMaskIntoConstraints = false
        list.rowHeight = 13
        list.rowSpacing = 2
        list.horizontalInset = 0
        list.elementGap = 5
        // 名称固定 58pt 列、数值按实测右对齐 —— 与改造前同一套列宽
        list.fixedTitleWidth = 58
        list.titleFont = SystemPaneStyle.microFont
        list.valueFont = MenuPanelStyle.smallValueFont
        list.titleColor = SystemPalette.foregroundSecondary
        list.trackColor = SystemPalette.track
        list.barColor = SystemPalette.process
        list.barHeight = 5
        // 进程行很窄，条可以画得更细一些
        list.minBarWidth = 8
        addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: leadingAnchor),
            list.trailingAnchor.constraint(equalTo: trailingAnchor),
            list.topAnchor.constraint(equalTo: topAnchor),
            list.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("进程资源榜")
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新榜单；rows 为空 = 不可得态（占位「—」，空条形）
    func update(_ rows: [Row], unavailableTip: String) {
        self.rows = rows
        self.unavailableTip = unavailableTip
        rebuild()
    }

    /// 把行数据铺成固定条数的自绘行规格
    private func rebuild() {
        var specs: [DrawnRowSpec] = []
        specs.reserveCapacity(capacity)
        for index in 0..<capacity {
            if index < rows.count {
                let row = rows[index]
                specs.append(DrawnRowSpec(title: row.name,
                                          value: row.valueText,
                                          progress: row.fraction,
                                          tone: row.isOver ? .warning : .normal))
            } else {
                // 不可得：占位「—」+ 空描边条
                specs.append(DrawnRowSpec(title: SystemPaneFormat.placeholder,
                                          value: SystemPaneFormat.placeholder,
                                          progress: 0,
                                          isEmptyBar: true))
            }
        }
        list.rows = specs
        list.rowToolTip = { [weak self] index in
            guard let self else { return "" }
            return index < self.rows.count ? self.rows[index].tip : self.unavailableTip
        }
    }
}

// MARK: - 行装配

extension SystemPaneView {

    /// 按维度构造进程榜行（首屏 Top-2 与「压力详情」Top-10 共用同一口径）
    static func processRows(_ snapshot: ProcessResourceSnapshot?,
                            metric: SystemProcessMetric,
                            limit: Int,
                            memoryTotal: UInt64?) -> [SystemProcessListView.Row] {
        SystemProcessBoard.rows(snapshot, metric: metric, limit: limit).map { usage in
            // 本应用那行显示「一览」：只换显示名，条形 / 数值 / 排序仍按采样原始值
            let displayName = AppProcessName.displayName(usage.name, pid: usage.pid)
            return SystemProcessListView.Row(
                name: displayName,
                fraction: SystemProcessBoard.barFraction(for: usage, metric: metric,
                                                        memoryTotal: memoryTotal),
                valueText: SystemProcessBoard.valueText(for: usage, metric: metric),
                isOver: metric == .cpu && usage.cpuPercent > 100,
                tip: SystemPaneTip.processRow(usage: usage, displayName: displayName,
                                              metric: metric, memoryTotal: memoryTotal))
        }
    }
}
