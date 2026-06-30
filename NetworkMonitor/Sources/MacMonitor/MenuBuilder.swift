import AppKit
import Foundation

/// 菜单构建器：根据今日统计数据构建下拉菜单
@MainActor
final class MenuBuilder {

    private let statsProvider: StatsProvider

    init(statsProvider: StatsProvider) {
        self.statsProvider = statsProvider
    }

    /// 构建完整的下拉菜单
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let stats = statsProvider.fetchTodayStats()

        // 标题栏
        menu.addItem(titleItem(title: "📊  macMonitor  今日概览"))
        menu.addItem(NSMenuItem.separator())

        // 快速摘要 — 指标卡片
        addSummarySection(to: menu, stats: stats)
        menu.addItem(NSMenuItem.separator())

        // 活跃软件排行
        addRankingSection(to: menu, stats: stats)
        menu.addItem(NSMenuItem.separator())

        // 系统资源
        addSystemSection(to: menu, stats: stats)
        menu.addItem(NSMenuItem.separator())

        // 操作按钮
        menu.addItem(actionItem(title: "📅  生成并查看每日报告", action: #selector(AppDelegate.showDailyReport)))
        menu.addItem(actionItem(title: "📆  生成每周报告", action: #selector(AppDelegate.showWeeklyReport)))
        menu.addItem(actionItem(title: "📂  打开报告文件夹", action: #selector(AppDelegate.openReportsFolder)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem(title: "🚀  开机自启", action: #selector(AppDelegate.toggleLaunchAtLogin)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem(title: "⏹  退出", action: #selector(AppDelegate.quit)))

        return menu
    }

    // MARK: - 标题

    private func titleItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - 快速摘要

    private func addSummarySection(to menu: NSMenu, stats: TodayStats) {
        let text = """
        ⏱ 活跃时间   \(formatDuration(stats.activeSeconds))
        ⌨️ 击键次数   \(formatNumber(stats.keyPressCount))
        💡 亮屏时长   \(formatDuration(stats.screenOnSeconds))
        🔋 系统内存   \(stats.memoryUsedMB)MB / \(stats.memoryTotalMB)MB
        """

        let item = NSMenuItem()
        let view = createLabelView(text: text, font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
        item.view = view
        menu.addItem(item)
    }

    // MARK: - 应用排行

    private func addRankingSection(to menu: NSMenu, stats: TodayStats) {
        let titleItem = NSMenuItem(title: "🏆  最活跃软件", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if stats.appRanking.isEmpty {
            let emptyItem = NSMenuItem(title: "   暂无数据", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for (index, app) in stats.appRanking.enumerated() {
            let rank = index + 1
            let duration = formatDuration(app.duration)
            // 限制应用名长度，保持对齐
            let name = app.name.count > 18 ? String(app.name.prefix(16)) + "…" : app.name
            let paddedName = name.padding(toLength: 20, withPad: " ", startingAt: 0)
            let text = "  \(rank).  \(paddedName)  \(duration)"

            let item = NSMenuItem()
            let view = createLabelView(text: text, font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
            item.view = view
            menu.addItem(item)
        }
    }

    // MARK: - 系统资源

    private func addSystemSection(to menu: NSMenu, stats: TodayStats) {
        let titleItem = NSMenuItem(title: "💻  资源占用", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let cpuText = String(format: "CPU   %.1f%%     内存 %dMB / %dMB", stats.cpuUsage, stats.memoryUsedMB, stats.memoryTotalMB)
        let netText = "↑ 上传 \(formatBytes(stats.netUploadSpeed))/s   ↓ 下载 \(formatBytes(stats.netDownloadSpeed))/s"

        let cpuItem = NSMenuItem()
        cpuItem.view = createLabelView(text: "  \(cpuText)", font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
        menu.addItem(cpuItem)

        let netItem = NSMenuItem()
        netItem.view = createLabelView(text: "  \(netText)", font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
        menu.addItem(netItem)
    }

    // MARK: - 操作按钮

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = NSApp.delegate
        return item
    }

    // MARK: - 辅助视图

    /// 创建纯文本标签视图（用于自定义菜单项）
    private func createLabelView(text: String, font: NSFont) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false

        let size = label.sizeThatFits(NSSize(width: 280, height: 1000))
        label.frame = NSRect(x: 12, y: 4, width: size.width, height: size.height)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: size.height + 8))
        view.addSubview(label)
        return view
    }

    // MARK: - 格式化

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)KB" }
        return String(format: "%.1fMB", Double(bytes) / 1024.0 / 1024.0)
    }
}
