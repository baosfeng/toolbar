import AppKit

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

    /// 快照自证专用（仅 DEBUG）：主面板关键区块在页面坐标系中的 frame
    func layoutMetricsForSnapshot() -> [(name: String, frame: NSRect)] {
        layoutSubtreeIfNeeded()
        let items: [(String, NSView)] = [
            ("hero", heroView),
            ("card-uncached", familyCards[0]),
            ("card-output", familyCards[1]),
            ("card-cache", familyCards[2]),
            ("card-req", familyCards[3]),
            ("chart-hourly", hourCard),
            ("chart-hourly-bars", hourBars),
            ("chart-trend", trendCard),
            ("card-cache-ring", cacheCard),
            ("card-proj", projectCard),
            ("card-model", modelCard),
            ("compare-card", compareCard),
            ("stateband", stateBand),
        ]
        return items.map { ($0.0, $0.1.convert($0.1.bounds, to: self)) }
    }

    /// 快照自证专用（仅 DEBUG）：项目 / 模型每行名称的可用宽度与截断状态
    ///
    /// available = 名称标签实到宽度；needed = 完整显示所需宽度；needed > available 即截断。
    func distroRowMetricsForSnapshot()
        -> [(name: String, available: CGFloat, needed: CGFloat, truncated: Bool, text: String)] {
        layoutSubtreeIfNeeded()
        var result: [(String, CGFloat, CGFloat, Bool, String)] = []
        for (block, rows) in [("project", projectRows), ("model", modelRows)] {
            for (index, row) in rows.enumerated() where !row.isHidden {
                let metric = row.metricsForSnapshot(in: self)
                result.append((block + "-" + String(index + 1), metric.available, metric.needed,
                               metric.needed > metric.available + 0.5, metric.text + " | " + metric.value))
            }
        }
        return result
    }

    /// 快照自证专用（仅 DEBUG）：Hero 各元素的字号与几何
    func heroMetricsForSnapshot() -> [(name: String, fontSize: CGFloat, frame: NSRect, needed: CGFloat, text: String)] {
        heroView.metricsForSnapshot(in: self)
    }
}
#endif
