import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 状态栏两种呈现路径（图标自绘 / 纯文本）

/// 从 `MenuBarManager.update()` 拆出（主文件撞 15 KiB 门禁）。
///
/// 两条路径互斥且必须成对：图标路径给 button 设 image 并清空 title，
/// 文本路径先摘掉 image —— 少写一半就会出现「切成文本后还挂着一张旧图」。
extension MenuBarManager {

    /// 有指标勾了「图标」时走自绘整条；返回 true 表示本次渲染已接管
    ///
    /// 为什么必须整条自绘：状态项按钮只有一枚图 + 一段字，
    /// 「↓10K [图表]7.01亿」这种中间一段是图标的混排只能画进同一张 template 图。
    /// 两行布局暂不做图标化（分行与自绘高度耦合，收益远小于风险）。
    func applyIconStatusIfNeeded(enabled: Set<MenuBarMetric>,
                                 alertPrefix: String,
                                 pausePrefix: String,
                                 separator: String,
                                 layout: MenuBarDisplayLogic.Layout,
                                 todayTraffic: UInt64,
                                 weekTraffic: UInt64) -> Bool {
        let iconMetrics = displayPreferences.iconMetrics
        guard !iconMetrics.isEmpty, layout == .singleLine else { return false }
        let segments = makeStatusSegments(enabled: enabled,
                                          snapshot: systemMonitor?.snapshot,
                                          todayTraffic: todayTraffic,
                                          weekTraffic: weekTraffic,
                                          tokenTotals: harnessUsage?.snapshot().totals)
        guard let image = MenuBarStatusRenderer.image(segments: segments,
                                                      iconMetrics: iconMetrics,
                                                      prefix: alertPrefix + pausePrefix,
                                                      separator: separator,
                                                      labelStyle: displayPreferences.labelStyle,
                                                      customLabels: displayPreferences.customLabels) else {
            return false
        }
        let button = statusItem.button
        if button?.image !== image {
            button?.image = image
            button?.imagePosition = .imageOnly
            button?.attributedTitle = NSAttributedString(string: "")
        }
        return true
    }

    /// 纯文本路径：先摘掉自绘图标，再写 attributedTitle
    func applyTextStatus(parts: [String],
                         alertPrefix: String,
                         pausePrefix: String,
                         layout: MenuBarDisplayLogic.Layout,
                         separator: String) {
        let button = statusItem.button
        if button?.image != nil {
            button?.image = nil
            button?.imagePosition = .noImage
        }
        let body = MenuBarDisplayLogic.statusTitle(parts: parts, layout: layout, separator: separator)
        let text = alertPrefix + pausePrefix + body
        if button?.attributedTitle.string != text {
            button?.attributedTitle = NSAttributedString(string: text)
        }
    }
}
