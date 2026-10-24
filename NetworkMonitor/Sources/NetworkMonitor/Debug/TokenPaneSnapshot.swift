#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - Token 页补充快照（仅 DEBUG）

/// Token 页取证 —— 等待真实索引进度 + 补拍状态页 / 滚到底部 / 分段宽度实测
///
/// 真实数据首屏由 `MenuPanelSnapshot` 的通用循环产出（menu-token-light.png / menu-token-dark.png）；
/// 本文件只补齐首屏之外的证据，避免快照主文件继续膨胀超过单文件体积上限。
@MainActor
enum TokenPaneSnapshot {

    /// 等一次按需索引跑完，返回真实快照（服务未装配时返回 nil）
    static func waitForSnapshot(harness: (any HarnessUsageServicing)?) async -> HarnessUsageSnapshot? {
        guard let harness else { return nil }
        let startedAt = Date()
        await withCheckedContinuation { continuation in
            harness.refreshIfNeeded { continuation.resume() }
        }
        let snapshot = harness.snapshot()
        AppContext.shared.logger.info("Token 快照：索引等待完成，耗时 \(Int(Date().timeIntervalSince(startedAt)))s，"
            + "会话 \(snapshot.indexedSessions)/\(snapshot.totalSessions)，"
            + "今日三项合计 \(snapshot.totals.today.totalTokens) token")
        return snapshot
    }

    /// 补齐证据：加载 / 空 / 数据源不可用三态（深浅色）+ 真实数据滚到底部 + 分段宽度实测
    static func capture(directory: URL, tokenSnapshot: HarnessUsageSnapshot?) {
        let availability = tokenSnapshot?.sourceAvailability ?? .available(toolPath: "/usr/local/bin/zstd")
        let missing = HarnessSourceAvailability.toolMissing(searchedPaths: ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"])
        let states: [(suffix: String, snapshot: HarnessUsageSnapshot)] = [
            ("loading", HarnessUsageSnapshot.empty(availability: availability,
                                                   state: .indexing(HarnessIndexProgress(completedFiles: 7,
                                                                                        totalFiles: 12,
                                                                                        currentFile: "session.jsonl.zstd",
                                                                                        parsedSessions: 7)))),
            ("empty", HarnessUsageSnapshot.empty(availability: availability, state: .ready)),
            ("unavailable", HarnessUsageSnapshot.empty(availability: missing,
                                                       state: .failed(message: missing.displayMessage))),
        ]
        for state in states {
            let panel = MenuPanelView()
            panel.updateToken(state.snapshot, notifySize: false)
            panel.select(tab: .token)
            let height = min(max(panel.desiredContentHeight, 180), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                MenuPanelSnapshot.render(view: panel, size: size, appearanceName: appearance,
                                         to: directory.appendingPathComponent("menu-token-\(state.suffix)-\(name).png"))
            }
        }

        if let tokenSnapshot {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                let panel = MenuPanelView()
                panel.updateToken(tokenSnapshot, notifySize: false)
                panel.select(tab: .token)
                let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                MenuPanelSnapshot.render(view: panel, size: size, appearanceName: appearance,
                                         to: directory.appendingPathComponent("menu-token-lower-\(name).png"),
                                         postLayout: { view in
                    (view as? MenuPanelView)?.scrollToBottomForSnapshot()
                })
            }
        }

        // 折叠区块展开态（手风琴详情布局自证）
        if let tokenSnapshot {
            let panel = MenuPanelView()
            panel.updateToken(tokenSnapshot, notifySize: false)
            panel.select(tab: .token)
            panel.tokenPane.expandAllSectionsForSnapshot()
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
            MenuPanelSnapshot.render(view: panel, size: size, appearanceName: .aqua,
                                     to: directory.appendingPathComponent("menu-token-expanded-light.png"),
                                     postLayout: { view in
                (view as? MenuPanelView)?.scrollForSnapshot(fraction: 0.55)
            })
        }

        // 真实数据：滚到「按天趋势」段，证明堆叠柱 / 斜纹空档 / 今日描边
        if let tokenSnapshot {
            let panel = MenuPanelView()
            panel.updateToken(tokenSnapshot, notifySize: false)
            panel.select(tab: .token)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
            MenuPanelSnapshot.render(view: panel, size: size, appearanceName: .aqua,
                                     to: directory.appendingPathComponent("menu-token-trend-light.png"),
                                     postLayout: { view in
                (view as? MenuPanelView)?.scrollForSnapshot(fraction: 0.42)
            })
        }

        // 交互状态：近 7 天 + 折线 + 比昨日（覆盖范围切换与两种图标形态）
        if let tokenSnapshot {
            let panel = MenuPanelView()
            panel.updateToken(tokenSnapshot, notifySize: false)
            panel.select(tab: .token)
            panel.tokenPane.applyStateForSnapshot(range: .d7, hourMode: .compare, trendMode: .line)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
            MenuPanelSnapshot.render(view: panel, size: size, appearanceName: .aqua,
                                     to: directory.appendingPathComponent("menu-token-d7-line-light.png"),
                                     postLayout: { view in
                (view as? MenuPanelView)?.scrollForSnapshot(fraction: 0.42)
            })
        }

        if let tokenSnapshot {
            writeChartData(directory: directory, snapshot: tokenSnapshot)
        }
        if let tokenSnapshot {
            writeLayoutMetrics(directory: directory, snapshot: tokenSnapshot)
        }
        writeSegmentMetrics(directory: directory)
        AppContext.shared.logger.info("Token 快照：补充状态完成（加载 / 空 / 不可用 / 滚到底 / 分段宽度实测）")
    }

    /// 导出关键区块几何（与原型 CSS 值逐项对照）
    private static func writeLayoutMetrics(directory: URL, snapshot: HarnessUsageSnapshot) {
        let panel = MenuPanelView()
        panel.updateToken(snapshot, notifySize: false)
        panel.select(tab: .token)
        panel.layoutSubtreeIfNeeded()
        let pane = panel.tokenPane
        var lines = ["pane_width_pt = \(Int(pane.bounds.width.rounded()))"]
        for item in pane.layoutMetricsForSnapshot() {
            let frame = item.frame
            lines.append(String(format: "%@: x=%.1f y=%.1f w=%.1f h=%.1f",
                                item.name, frame.minX, frame.minY, frame.width, frame.height))
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-layout-metrics.txt"),
                        atomically: true, encoding: .utf8)
    }

    /// 导出小时请求数与近 30 天复用率（核对 24 槽定位与孤立点分布）
    private static func writeChartData(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = ["# 今日小时请求数（24 槽，缺省 = -）"]
        for slot in snapshot.todayHourly {
            let requests = slot.usage.map { String($0.requestCount) } ?? "-"
            lines.append("hour=\(slot.hour) requests=\(requests)")
        }
        lines.append("# 近 30 天缓存复用率（缺省 = -）")
        let lastDay = HarnessTokenTimeWindow.dayKey(for: Date())
        let dailyMap = snapshot.daily.reduce(into: [String: HarnessTokenUsage]()) { result, item in
            result[item.day] = item.usage
        }
        for key in TokenFormat.dayKeys(lastDay: lastDay, days: 30) {
            let rate = dailyMap[key].flatMap {
                HarnessCacheHitRate.compute(cacheRead: $0.cacheRead, uncachedInput: $0.uncachedInput)
            }
            lines.append("day=\(key) rate=\(rate.map { String(format: "%.4f", $0) } ?? "-")")
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-chart-data.txt"),
                        atomically: true, encoding: .utf8)
    }

    /// 五段分段宽度实测（证明 320pt 下都不截断）
    private static func writeSegmentMetrics(directory: URL) {
        let metrics = MenuTabBarView.segmentMetrics()
        let lines = metrics.map { item in
            String(format: "%@: content = %.1fpt, available = %.1fpt, slack = %.1fpt, truncated = %@",
                   item.title, item.content, item.available, item.available - item.content,
                   item.content > item.available ? "YES" : "NO")
        }
        let text = "panel_width_pt = \(Int(MenuPanelStyle.panelWidth))\n" + lines.joined(separator: "\n") + "\n"
        do {
            try text.write(to: directory.appendingPathComponent("menu-token-tabbar-metrics.txt"),
                           atomically: true, encoding: .utf8)
        } catch {
            AppContext.shared.logger.error("Token 快照：分段宽度指标写入失败 \(error.localizedDescription)")
        }
    }
}
#endif