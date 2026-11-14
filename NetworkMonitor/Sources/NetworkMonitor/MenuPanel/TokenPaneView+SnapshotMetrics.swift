import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 页几何 / 截断度量（仅 DEBUG，从 TokenPaneView.swift 拆出：单文件体积门禁）

/// 快照自证用的度量接口：区块 frame、分布行名称可用宽度、Hero 字号
///
/// 只读不写，因此可以和主类分文件（写成员如 applyStateForSnapshot 仍留在主类）。
#if DEBUG
extension TokenPaneView {

    /// 快照自证专用（仅 DEBUG）：小时卡 head / meta 两行各元素的 frame 与「完整显示所需宽度」
    ///
    /// needed 大于 frame 宽度即截断；相邻元素 gap 为负即重叠。
    /// - Parameter reference: 取 frame 的参照视图（默认小时卡本身；独立渲染时传渲染实例）
    func hourCardMetricsForSnapshot(in reference: TokenCardRow? = nil)
        -> [(name: String, frame: NSRect, needed: CGFloat, text: String)] {
        layoutSubtreeIfNeeded()
        func needed(_ view: NSView) -> CGFloat {
            if let label = view as? NSTextField { return label.intrinsicContentSize.width }
            return view.fittingSize.width
        }
        func text(_ view: NSView) -> String {
            (view as? NSTextField)?.stringValue ?? (view as? NSButton)?.title ?? ""
        }
        let items: [(String, NSView)] = [
            ("head-hourTitle", hourTitle),
            ("head-daySegment", daySegment),
            ("meta-hourMeta", hourMeta),
            ("meta-viewAction", viewAction),
            ("meta-hourAction", hourAction),
        ]
        let anchor = reference ?? hourCard
        return items.map { ($0.0, $0.1.convert($0.1.bounds, to: anchor), needed($0.1), text($0.1)) }
    }

    /// 快照自证专用（仅 DEBUG）：当前屏的区块与屏切换条在页面坐标系中的 frame
    ///
    /// 只量当前可见屏：隐藏的屏栈 frame 全为零，量了也没意义；4 屏各自的几何由
    /// TokenPaneSnapshot+Screens.swift 逐屏取证。缓存 / 排行屏是整块视图，
    /// 由 screen-stack 一行覆盖，块内不再逐个列（内部块不是主面板的子视图）。
    func layoutMetricsForSnapshot() -> [(name: String, frame: NSRect)] {
        layoutSubtreeIfNeeded()
        var items: [(String, NSView)] = [
            ("screenbar", screenControl),
            ("screen-frame", screenFrames[safe: screen.rawValue] ?? self),
        ]
        items.append(contentsOf: blockMeasureTargets())
        return items.map { ($0.0, $0.1.convert($0.1.bounds, to: self)) }
    }

    /// 当前屏里独立成块的视图（缓存屏 / 排行屏内部块不经这里）
    private func blockMeasureTargets() -> [(String, NSView)] {
        switch screen {
        case .overview:
            return [("hero", heroView), ("card-uncached", familyCards[0]), ("card-output", familyCards[1]),
                    ("card-cache", familyCards[2]), ("card-req", familyCards[3]),
                    ("chart-trend-mini", overviewTrendCard), ("compare-card", compareCard),
                    ("footer-stateband", overviewBand)]
        case .usage:
            return [("chart-hourly", hourCard), ("chart-hourly-bars", hourBars),
                    ("chart-trend", trendCard), ("footer-stateband", usageBand)]
        case .cache:
            return [("footer-note", cacheScreen.footerView)]
        case .ranking:
            return [("footer-stateband", rankingBand)]
        }
    }

    /// 快照自证专用（仅 DEBUG）：排行屏 Top 8 行名称的可用宽度与截断状态
    ///
    /// 项目 / 模型两个维度各量一遍（维度分段切换后行数据整套换掉，只量一个维度会漏）。
    /// available = 名称标签实到宽度；needed = 完整显示所需宽度；needed > available 即截断。
    func distroRowMetricsForSnapshot()
        -> [(name: String, available: CGFloat, needed: CGFloat, truncated: Bool, text: String)] {
        layoutSubtreeIfNeeded()
        var result: [(String, CGFloat, CGFloat, Bool, String)] = []
        let original = rankScreen.dimension
        for dimension in [TokenDistroDimension.projects, .models] {
            rankScreen.setDimensionForSnapshot(dimension)
            if let lastModel { rankScreen.update(model: lastModel) }
            layoutSubtreeIfNeeded()
            let prefix = dimension == .projects ? "project" : "model"
            for (index, row) in rankScreen.rowProbesForSnapshot().enumerated() {
                result.append((prefix + "-" + String(index + 1), row.titleAvailable, row.titleNeeded,
                               row.titleNeeded > row.titleAvailable + 0.5,
                               row.title + " | " + row.value + "  " + row.secondary))
            }
        }
        rankScreen.setDimensionForSnapshot(original)
        if let lastModel { rankScreen.update(model: lastModel) }
        return result
    }

    /// 快照自证专用（仅 DEBUG）：Hero 各元素的字号与几何
    func heroMetricsForSnapshot() -> [(name: String, fontSize: CGFloat, frame: NSRect, needed: CGFloat, text: String)] {
        heroView.metricsForSnapshot(in: self)
    }
}
#endif
