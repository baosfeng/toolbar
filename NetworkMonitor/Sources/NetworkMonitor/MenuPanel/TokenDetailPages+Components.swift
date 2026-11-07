import AppKit
import NetworkMonitorCore

// MARK: - Token 二级页 · 共用组件

/// 二级页共用卡片组件（hero / head / keyRow / axis / 两列栅格 / note / 分片占比）
///
/// 从 `TokenDetailPages.swift` 拆出：六个二级页共用这一套视觉，主文件只留容器与滚动。
extension TokenDetailPaneView {

    // MARK: - 组件

    func hero(_ value: String, unit: String, sub: String) -> NSView {
        let valueLabel = MenuPanelLabel.text(value, font: TokenPaneStyle.heroFont,
                                             color: TokenPaneStyle.secondaryText)
        let unitLabel = MenuPanelLabel.text(unit, font: TokenPaneStyle.heroUnitFont,
                                            color: TokenPaneStyle.tertiaryText)
        let row = NSStackView(views: [valueLabel, unitLabel])
        row.orientation = .horizontal
        row.alignment = .lastBaseline
        row.spacing = 3
        row.setAccessibilityLabel(value + " " + unit)

        let subLabel = MenuPanelLabel.text(sub, font: TokenPaneStyle.noteFont,
                                           color: TokenPaneStyle.tertiaryText)
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 0
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [row, subLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        subLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func head(_ title: String, meta: String) -> NSView {
        let head = TokenCardHead(title: title)
        head.update(meta: meta)
        return head
    }

    /// 键值行；stacked = 标题与数值分两行排（用于「标题 + 长说明」单行放不下的卡）
    func keyRow(_ title: String, _ value: String,
                color: NSColor = TokenPaneStyle.secondaryText,
                stacked: Bool = false) -> NSView {
        let row = TokenKeyRowView(stacked: stacked)
        row.update(title: title, value: value, color: color)
        return row
    }

    func axisView(_ labels: [String]) -> NSView {
        let axis = TokenAxisView()
        axis.update(labels: labels)
        return axis
    }

    /// 两列键值栅格（按行优先填两列）
    func twoColumn(_ rows: [NSView]) -> NSView {
        var left: [NSView] = []
        var right: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index % 2 == 0 { left.append(row) } else { right.append(row) }
        }
        func column(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            return stack
        }
        let stack = NSStackView(views: [column(left), column(right)])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    func note(_ text: String) -> NSView {
        let card = TokenBoxView()
        let noteView = TokenNoteView()
        noteView.update(text)
        card.setRows([noteView])
        return card
    }

    func splitShares(_ bucket: TokenBucket) -> [Double] {
        guard bucket.total > 0 else { return [0, 0, 0] }
        return [Double(bucket.cache) / Double(bucket.total),
                Double(bucket.uncached) / Double(bucket.total),
                Double(bucket.output) / Double(bucket.total)]
    }

    /// 返回条被页面改写时同步面包屑与右侧说明
    func overrideCrumb(_ text: String, meta: String) {
        crumbLabel.stringValue = text
        metaLabel.stringValue = meta
    }
}
