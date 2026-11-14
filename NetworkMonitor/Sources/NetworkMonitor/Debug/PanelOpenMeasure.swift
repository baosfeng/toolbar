#if DEBUG
import AppKit
import NetworkMonitorCore
import QuartzCore

// MARK: - 面板打开耗时测量（仅 DEBUG）

/// 点击状态栏到面板可见的分阶段计时 — **仅 DEBUG**
///
/// 走的是与真实点击完全相同的一条路径：`MenuBarManager.openPanelForEvidence()` → `togglePanel()`
/// → `MenuPanelController.toggle/show`，不做任何「测试专用捷径」，避免测出来的不是用户体感。
///
/// 触发：
/// ```
/// NM_MEASURE_PANEL_ROUNDS=20 NM_MEASURE_GAP_MS=0 NM_MEASURE_OUT=/tmp/x.txt \
///   /Applications/一览.app/Contents/MacOS/一览 --measure-panel-open
/// ```
/// - `NM_MEASURE_PANEL_ROUNDS`：轮次（默认 20，下限 10；第 1 轮 = 首次打开）
/// - `NM_MEASURE_GAP_MS`：每轮打开前额外静置（0 = 连续开合，>0 = 模拟闲置后真实点击）
/// - `NM_MEASURE_OUT`：报告路径（默认 /tmp/nm-panel-open.txt，同时写 stdout）
@MainActor
enum PanelOpenMeasure {

    static let roundsEnvKey = "NM_MEASURE_PANEL_ROUNDS"
    /// 预热实验：none | showhide（真实开合一次后立刻收起）
    static let prewarmEnvKey = "NM_MEASURE_PREWARM"
    static let gapEnvKey = "NM_MEASURE_GAP_MS"
    static let outputEnvKey = "NM_MEASURE_OUT"
    private static let defaultOutputPath = "/tmp/nm-panel-open.txt"
    private static let defaultRounds = 20
    /// 启动后延迟：等 1 秒定时器、Token 索引、首次采样稳定后再测
    private static let startupDelayNanoseconds: UInt64 = 1_500_000_000
    /// 收起后等待：越过 popover 关闭动画与 toggle 的 0.25 秒防重开窗口
    private static let closeSettleNanoseconds: UInt64 = 700_000_000
    /// 展开后停留：等展开动画结束再收起，避免下一轮量到动画中的中间态
    private static let openSettleNanoseconds: UInt64 = 450_000_000

    private static var logger: LoggingService { AppContext.shared.logger }

    /// 入口：命令行 / 环境变量要求时启动测量；未要求立即返回
    static func runIfRequested(manager: MenuBarManager?) {
        guard PanelOpenProbe.requested, let manager else { return }
        let rounds = max(10, intValue(roundsEnvKey) ?? defaultRounds)
        let gap = TimeInterval(intValue(gapEnvKey) ?? 0) / 1000
        let prewarm = ProcessInfo.processInfo.environment[prewarmEnvKey] ?? "none"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: startupDelayNanoseconds)
            if prewarm == "showhide" {
                let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                manager.prewarmPanel()
                let frontAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let window = manager.panelWindowForMeasure()
                let windowState = "isVisible=\(window?.isVisible ?? false) alpha=\(window?.alphaValue ?? -1)"
                writeStdout("# 预热自检：前台 App \(frontBefore ?? "nil") → \(frontAfter ?? "nil")；"
                            + "预热后 popover 仍展开=\(manager.isPanelShownForMeasure)；窗口 \(windowState)")
                // 预热与真实打开之间留出防重开窗口（toggle 有 0.25 秒保护）
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            await measure(manager: manager, rounds: rounds, gap: gap, prewarm: prewarm)
            NSApp.terminate(nil)
        }
    }

    // MARK: - 测量主流程

    private static func measure(manager: MenuBarManager, rounds: Int, gap: TimeInterval,
                                prewarm: String) async {
        var skipped = 0
        var heights: [CGFloat] = []
        PanelOpenProbe.begin()
        defer { PanelOpenProbe.finish() }
        for _ in 0..<rounds {
            // 关掉上一轮：等到真的收起为止（关合是动画异步的，读晚了会把这一轮量成空转）
            await closeAndWait(manager: manager)
            if gap > 0 {
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
            PanelOpenProbe.beginRound()
            PanelOpenProbe.mark("00 toggle 入口")
            manager.openPanelForEvidence()
            let opened = manager.isPanelShownForMeasure
            // 首帧落屏：把待处理的绘制与 CA 提交同步刷出去，这一刻才是用户真正「看到」面板
            CATransaction.flush()
            if let window = manager.panelWindowForMeasure() {
                window.displayIfNeeded()
                window.display()
            }
            CATransaction.flush()
            PanelOpenProbe.mark("07 首帧可见")
            heights.append(manager.panelContentSizeForMeasure.height)
            // 再等一轮 runloop：确认没有把活推迟到下一帧才落定
            await nextRunloopTurn()
            PanelOpenProbe.mark("08 一轮 runloop 后")
            PanelOpenProbe.endRound(keep: opened)
            if !opened { skipped += 1 }
            try? await Task.sleep(nanoseconds: openSettleNanoseconds)
        }
        let report = makeReport(rounds: PanelOpenProbe.rounds,
                                skipped: skipped, heights: heights,
                                roundsWanted: rounds, gap: gap, prewarm: prewarm)
        emit(report)
    }

    /// 收起面板并等它真的收起（轮询到 isShown == false，最长 2 秒）
    private static func closeAndWait(manager: MenuBarManager) async {
        guard manager.isPanelShownForMeasure else { return }
        manager.closePanelForMeasure()
        let deadline = CACurrentMediaTime() + 2.0
        while manager.isPanelShownForMeasure, CACurrentMediaTime() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // toggle 有 0.25 秒防重开保护（吞掉「点状态栏先收起再展开」的重复动作）：
        // 关闭动画结束时 lastCloseDate 才更新，这里再等一段，保证每次都能真正打开
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    // MARK: - 报告

    private static func makeReport(rounds: [PanelOpenProbe.Round], skipped: Int,
                                   heights: [CGFloat], roundsWanted: Int,
                                   gap: TimeInterval, prewarm: String) -> String {
        guard rounds.count > 1 else {
            return "测量失败：有效轮次 \(rounds.count)（面板未真正打开 \(skipped) 轮）"
        }
        let cold = rounds[0]
        let warm = Array(rounds.dropFirst())
        let visibleName = "07 首帧可见"
        let enterName = "00 toggle 入口"

        var out: [String] = []
        out.append("# 面板打开耗时测量（仅 DEBUG，单位 ms）")
        out.append("# 入口：MenuBarManager.togglePanel（与点击状态栏同一条路径）")
        out.append("# 口径：00 toggle 入口 → 07 首帧可见（show 返回后再强制 display + CA 提交，即真实落屏）")
        out.append("# 轮次：要求 \(roundsWanted)，有效 \(rounds.count)，面板未打开而丢弃 \(skipped)；每轮开前静置 \(Int(gap * 1000)) ms")
        out.append("# 第 1 轮 = 应用启动后首次打开（预热模式 \(prewarm)）；其余 \(warm.count) 轮 = 收起后再打开")
        out.append("# contentSize.height：" + heights.map { Int($0.rounded()) }.map(String.init).joined(separator: ","))
        out.append("")

        // 总耗时（点击 → 可见）
        let warmTotals = warm.map { total($0, enter: enterName, visible: visibleName) }
        let coldTotal = total(cold, enter: enterName, visible: visibleName)
        out.append("## 点击 → 面板可见"
            + "\n\n| 场景 | 耗时 |\n| --- | ---: |"
            + "\n| 首次打开（应用启动后第一下） | \(ms(coldTotal)) ms |"
            + "\n| 再次打开 p50 | \(ms(percentile(warmTotals, 0.5))) ms |"
            + "\n| 再次打开 p95 | \(ms(percentile(warmTotals, 0.95))) ms |"
            + "\n| 再次打开 min~max | \(ms(warmTotals.min() ?? 0)) ~ \(ms(warmTotals.max() ?? 0)) ms |")
        out.append("")

        // 阶段耗时（顺序打点：某段 = 与下一点之差）
        let stageOrder = stageNames(of: warm)
        out.append("## 阶段耗时")
        out.append("| 阶段 | p50 | p95 | min | max | 首次打开 |")
        out.append("| --- | ---: | ---: | ---: | ---: | ---: |")
        for name in stageOrder {
            let values = warm.compactMap { value(of: name, in: $0) }
            let coldValue = value(of: name, in: cold)
            let cells = [name, ms(percentile(values, 0.5)), ms(percentile(values, 0.95)),
                         ms(values.min() ?? 0), ms(values.max() ?? 0), ms(coldValue ?? 0)]
            out.append("| " + cells.joined(separator: " | ") + " |")
        }
        out.append("")

        // 累计打点（bucket：可嵌套重入，报总耗时与次数）
        let bucketOrder = bucketNames(of: warm)
        if !bucketOrder.isEmpty {
            out.append("## 重入整段累计（同一轮内累计次数与总耗时）")
            out.append("| 项目 | p50 总耗时 | p95 总耗时 | 次数(min~max) | 首次总耗时 |")
            out.append("| --- | ---: | ---: | ---: | ---: |")
            for name in bucketOrder {
                let totals = warm.compactMap { $0.buckets[name]?.total }.map { $0 * 1000 }
                let counts = warm.compactMap { $0.buckets[name]?.count }
                let coldTotalValue = (cold.buckets[name]?.total ?? 0) * 1000
                let countText: String
                if let low = counts.min(), let high = counts.max() {
                    countText = low == high ? "\(low)" : "\(low)~\(high)"
                } else {
                    countText = "-"
                }
                out.append("| \(name) | \(ms(percentile(totals, 0.5))) | \(ms(percentile(totals, 0.95))) | \(countText) | \(ms(coldTotalValue)) |")
            }
            out.append("")
        }

        // 逐轮原始值（判断波动与冷热差异）
        out.append("## 逐轮原始（点击 → 可见，ms）")
        var raw: [String] = []
        for (index, round) in rounds.enumerated() {
            let label = index == 0 ? "首" : "\(index + 1)"
            raw.append("\(label):\(ms(total(round, enter: enterName, visible: visibleName)))")
        }
        out.append(raw.joined(separator: "  "))
        out.append("")

        // 机器可读块（改前 / 改后 diff 用）
        out.append("## TSV")
        out.append("stage\tcount\tp50\tp95\tmin\tmax\tcold")
        func tsv(_ name: String, _ values: [Double], _ coldValue: Double?) -> String {
            [name, "\(values.count)", ms(percentile(values, 0.5)), ms(percentile(values, 0.95)),
             ms(values.min() ?? 0), ms(values.max() ?? 0), ms(coldValue ?? 0)].joined(separator: "\t")
        }
        out.append(tsv("TOTAL 点击→可见", warmTotals, coldTotal))
        for name in stageOrder {
            out.append(tsv(name, warm.compactMap { value(of: name, in: $0) }, value(of: name, in: cold)))
        }
        for name in bucketOrder {
            let totals = warm.compactMap { $0.buckets[name]?.total }.map { $0 * 1000 }
            let coldTotalValue = (cold.buckets[name]?.total ?? 0) * 1000
            out.append(tsv("bucket:\(name)", totals, coldTotalValue))
        }
        return out.joined(separator: "\n")
    }

    /// 一轮的总耗时（点击入口 → 首帧可见）；缺打点时按最后一点兜底
    private static func total(_ round: PanelOpenProbe.Round, enter: String, visible: String) -> Double {
        guard let first = round.marks.first(where: { $0.name == enter }) ?? round.marks.first else { return 0 }
        let last = round.marks.first(where: { $0.name == visible }) ?? round.marks.last ?? first
        return max(0, last.time - first.time)
    }

    /// 阶段名（按首次出现顺序；不含末点）
    private static func stageNames(of rounds: [PanelOpenProbe.Round]) -> [String] {
        var names: [String] = []
        for round in rounds {
            for index in 0..<max(0, round.marks.count - 1) {
                let name = round.marks[index].name
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// 单轮里某阶段耗时（秒）；该阶段不存在时 nil
    private static func value(of name: String, in round: PanelOpenProbe.Round) -> Double? {
        guard let index = round.marks.firstIndex(where: { $0.name == name }),
              index + 1 < round.marks.count else { return nil }
        return round.marks[index + 1].time - round.marks[index].time
    }

    private static func bucketNames(of rounds: [PanelOpenProbe.Round]) -> [String] {
        var names: [String] = []
        for round in rounds {
            for name in round.buckets.keys.sorted() where !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    // MARK: - 格式化

    private static func ms(_ seconds: Double) -> String {
        String(format: "%.1f", seconds * 1000)
    }

    /// 分位（nearest-rank，样本少时也稳定）
    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count - 1)).rounded())
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    // MARK: - 输出

    private static func emit(_ report: String) {
        let path = ProcessInfo.processInfo.environment[outputEnvKey] ?? defaultOutputPath
        do {
            try report.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            logger.info("面板打开测量：报告已写入 \(path)")
        } catch {
            logger.error("面板打开测量：报告写入失败 \(error.localizedDescription)")
        }
        // 终端直接可见（不经过日志系统，便于 CI 抓 stdout）
        writeStdout(report)
    }

    /// 直接写 stdout（不经日志系统，便于脚本抓取）
    private static func writeStdout(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    // MARK: - 工具

    private static func nextRunloopTurn() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private static func intValue(_ key: String) -> Int? {
        ProcessInfo.processInfo.environment[key].flatMap(Int.init)
    }
}
#endif
