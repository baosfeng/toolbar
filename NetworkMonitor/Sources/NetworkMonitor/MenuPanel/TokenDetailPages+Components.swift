import AppKit
import NetworkMonitorCore

// MARK: - Token 二级页 · 共用组件（转发到 TokenContentKit）

/// 三张二级页的卡片组件 —— 实现全部在 TokenContentKit（TokenScreenContent.swift）
///
/// 为什么保留这一层转发：缓存屏与排行屏用同一套组件，若二级页再各写一份，
/// 「卡头 / 键值行 / 两列栅格」会立刻分叉（改一处漏一处）。这里只做名字映射，
/// 二级页（+Charts / +Buckets）的调用点零改动。
extension TokenDetailPaneView {

    func hero(_ value: String, unit: String, sub: String) -> NSView {
        TokenContentKit.hero(value, unit: unit, sub: sub)
    }

    func head(_ title: String, meta: String) -> NSView {
        TokenContentKit.head(title, meta: meta)
    }

    func keyRow(_ title: String, _ value: String,
                color: NSColor = TokenPaneStyle.secondaryText,
                stacked: Bool = false) -> NSView {
        TokenContentKit.keyRow(title, value, color: color, stacked: stacked)
    }

    func axisView(_ labels: [String]) -> NSView {
        TokenContentKit.axisView(labels)
    }

    func twoColumn(_ rows: [NSView]) -> NSView {
        TokenContentKit.twoColumn(rows)
    }

    func note(_ text: String) -> NSView {
        TokenContentKit.note(text)
    }

    func splitShares(_ bucket: TokenBucket) -> [Double] {
        TokenContentKit.splitShares(bucket)
    }

    /// 返回条被页面改写时同步面包屑与右侧说明
    func overrideCrumb(_ text: String, meta: String) {
        crumbLabel.stringValue = text
        metaLabel.stringValue = meta
    }
}
