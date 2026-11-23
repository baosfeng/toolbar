import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - Token 屏内容构建（屏与二级页共用同一套卡片组件）

/// 共享卡片组件 —— 缓存屏 / 排行屏 / 三个二级页全部从这里取
///
/// 为什么单独抽出来：改前「缓存命中 / 按项目 / 按模型」是二级页里的一套卡片构建，
/// 主面板又自己写了一套环 / 占比条 / 分布行；同一份数据两条渲染路径，口径迟早分叉。
/// 现在组件只在这里定义一次，二级页（TokenDetailPages+Components 转发）与屏共用。
@MainActor
enum TokenContentKit {

    /// 大数字 + 单位 + 副标题（二级页顶部）
    static func hero(_ value: String, unit: String, sub: String) -> NSView {
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

    /// 卡头：标题 + 弹簧 + 说明
    static func head(_ title: String, meta: String) -> NSView {
        let head = TokenCardHead(title: title)
        head.update(meta: meta)
        return head
    }

    /// 键值行；stacked = 标题与数值分两行排（标题 + 长说明单行放不下时用）
    static func keyRow(_ title: String, _ value: String,
                       color: NSColor = TokenPaneStyle.secondaryText,
                       stacked: Bool = false) -> NSView {
        let row = TokenKeyRowView(stacked: stacked)
        row.update(title: title, value: value, color: color)
        return row
    }

    static func axisView(_ labels: [String]) -> NSView {
        let axis = TokenAxisView()
        axis.update(labels: labels)
        return axis
    }

    /// 两列键值栅格（按行优先填两列）
    static func twoColumn(_ rows: [NSView]) -> NSView {
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

    /// 口径说明卡
    static func note(_ text: String) -> NSView {
        let card = TokenBoxView()
        let noteView = TokenNoteView()
        noteView.update(text)
        card.setRows([noteView])
        return card
    }

    /// 对照行（名称 + 横条 + 数值）
    static func compareRow(name: String, text: String, fraction: Double, color: NSColor) -> NSView {
        let row = TokenCompareRowView()
        row.update(name: name, text: text, fraction: fraction, color: color)
        return row
    }

    /// 单桶三段占比（缓存读 / 未缓存 / 输出）
    static func splitShares(_ bucket: TokenBucket) -> [Double] {
        guard bucket.total > 0 else { return [0, 0, 0] }
        return [Double(bucket.cache) / Double(bucket.total),
                Double(bucket.uncached) / Double(bucket.total),
                Double(bucket.output) / Double(bucket.total)]
    }
}
