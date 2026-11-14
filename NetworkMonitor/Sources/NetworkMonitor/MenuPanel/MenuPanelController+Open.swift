import AppKit
import NetworkMonitorCore

// MARK: - 菜单面板（显示 / 收起 / 刷新）

/// 面板打开与刷新链路 — 从 MenuPanelController.swift 拆出（主文件贴近单文件 15 KiB 上限，
/// 且打开路径要逐阶段打点，见 PanelOpenProbe）。
///
/// 刷新分层不变：1 秒速率、5 秒中频、事件驱动剪贴板、打开时强制全量一次。
extension MenuPanelController {

    // MARK: - 显示 / 收起

    /// 状态栏按钮点击入口：已展开则收起，否则在按钮下方展开
    func toggle(relativeTo rect: NSRect, of view: NSView) {
        if popover.isShown {
            close()
            return
        }
        // transient 行为下，点击状态栏按钮会先自动收起再触发按钮动作：
        // 极短时间内的再次 toggle 视为「本次关闭」的续动作，不再重新展开。
        guard Date().timeIntervalSince(lastCloseDate) > 0.25 else { return }
        show(relativeTo: rect, of: view)
    }

    /// 展开面板并强制全量刷新
    func show(relativeTo rect: NSRect, of view: NSView) {
        // 【时序敏感】必须在 popover 成为 key window 之前同步记录目标 App，
        // 否则 frontmost 会变成本 App，合成的 ⌘V 永远落回自己（见 ClipboardPaster 注释）。
        PanelOpenProbe.mark("01 recordTargetApplication")
        paster.recordTargetApplication()
        PanelOpenProbe.mark("02 refreshAll")
        refreshAll()
        PanelOpenProbe.mark("03 popover.show")
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        PanelOpenProbe.mark("04 updateContentSize(force)")
        updateContentSize(force: true)
        PanelOpenProbe.mark("05 makeFirstResponder")
        if let window = popover.contentViewController?.view.window {
            window.makeFirstResponder(content)
        }
        PanelOpenProbe.mark("06 show 返回")
    }

    // MARK: - 预热

    /// 启动后预热一次：把 NSPopover 的窗口、约束引擎与首帧绘制提前建好
    ///
    /// NSPopover 的窗口在**第一次 show 时**才创建，实测「窗口 + 整棵约束引擎 + 首帧绘制」
    /// 占首次打开约 375ms（再次打开只需 60ms 左右）；启动后先在真实路径上开一次再立刻收起，
    /// 把这份一次性开销挪到用户点击之前。
    ///
    /// 不可见性：全程在同一个 runloop 轮次内完成（show → 窗口 alpha 归零 → 收起），
    /// 窗口在任何一次提交前就已透明，用户看不到弹出。
    func prewarmPanelIfNeeded(relativeTo rect: NSRect, of view: NSView) {
        guard !hasPrewarmed, !popover.isShown else { return }
        hasPrewarmed = true
        let savedAnimates = popover.animates
        popover.animates = false
        defer { popover.animates = savedAnimates }
        // 数据先就位（首屏内容 + 内容树布局），再开窗
        refreshAll()
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        window?.alphaValue = 0
        popover.performClose(nil)
        window?.alphaValue = 1
        logger.info("面板预热完成（首次打开的窗口与布局开销已提前付掉）")
    }

    /// 收起面板
    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// 是否已展开
    var isShown: Bool { popover.isShown }

    // MARK: - 刷新

    /// 每秒调用（由状态栏定时器驱动）：速率必刷，其余按 5 秒节流
    func tick() {
        // 计费刷新与面板是否展开无关：收起时也要拉余额做阈值提醒
        // （60s 节流与 429 退避在 BillingMonitor 内部，这里每秒调用是安全的）
        billingMonitor?.refresh()
        guard popover.isShown else { return }
        sampleHistory()
        // 系统页：每秒推进历史，视图按 5 秒节流刷新（内部再判一次展开态，重复无害）
        systemTick()
        content.updateSpeeds(down: max(monitor.downloadSpeed, 0),
                             up: max(monitor.uploadSpeed, 0),
                             downHistory: downHistory,
                             upHistory: upHistory)
        let now = Date()
        guard now.timeIntervalSince(lastMidRefresh) >= Self.midInterval else { return }
        lastMidRefresh = now
        refreshMidFrequency()
    }

    /// 采样折线（仅面板展开时采样，避免无谓累积）
    func sampleHistory() {
        downHistory.append(max(monitor.downloadSpeed, 0))
        upHistory.append(max(monitor.uploadSpeed, 0))
        if downHistory.count > Self.maxHistory { downHistory.removeFirst(downHistory.count - Self.maxHistory) }
        if upHistory.count > Self.maxHistory { upHistory.removeFirst(upHistory.count - Self.maxHistory) }
    }

    /// 全量刷新（面板打开时调用一次）
    ///
    /// 期间的分页更新会把「内容变了」逐项通知上来，若每次都重算尺寸（layoutSubtreeIfNeeded +
    /// fittingSize），一次打开要跑 6 遍整棵树的布局 —— 冷启动实测占 70% 的打开耗时。
    /// 这里把整段收进批处理，数据全部落定后统一算一次高度。
    func refreshAll() {
        lastMidRefresh = Date()
        beginContentBatch()
        defer { endContentBatch() }
        PanelOpenProbe.mark("B1 sampleHistory")
        sampleHistory()
        PanelOpenProbe.mark("B2 updateSpeeds")
        content.updateSpeeds(down: max(monitor.downloadSpeed, 0),
                             up: max(monitor.uploadSpeed, 0),
                             downHistory: downHistory,
                             upHistory: upHistory)
        PanelOpenProbe.mark("B3 refreshMidFrequency")
        refreshMidFrequency()
        PanelOpenProbe.mark("B4 refreshClipboard")
        refreshClipboard()
        // 系统页：打开面板立即采一帧再渲染（首帧 CPU/磁盘速率为 nil，显示「—」）
        PanelOpenProbe.mark("B5 systemMonitor.poll")
        systemMonitor?.poll()
        PanelOpenProbe.mark("B6 refreshSystem")
        refreshSystem()
        // 传送页：收起期间只记账不推视图，这里补推一次（否则开面板会看到旧状态带）
        PanelOpenProbe.mark("B6.5 transfer.refreshNow")
        transferController?.refreshNow()
        // 额度页：打开面板强制刷新一次（monitor 内部处理未配置/退避）
        PanelOpenProbe.mark("B7 billing.refresh(force)")
        billingMonitor?.refresh(force: true)
        // Token 页：先用库里已有快照渲染，再触发后台增量索引（不阻塞面板）
        PanelOpenProbe.mark("B8 refreshToken")
        refreshToken()
        PanelOpenProbe.mark("B9 updateContentSize(force)")
        updateContentSize(force: true)
        PanelOpenProbe.mark("B10 refreshAll 结束")
    }

    /// 中频刷新：今日流量 / 近 6 日柱状图 / 活跃进程 / 系统信息
    func refreshMidFrequency() {
        PanelOpenProbe.mark("B3.1 trafficTracker.update")
        trafficTracker.update()
        let bars = PanelOpenProbe.bucket("recentDays") {
            MenuPanelMetrics.recentDays(entries: trafficTracker.weekEntries, limit: 6)
        }
        PanelOpenProbe.mark("B3.2 updateTraffic")
        content.updateTraffic(todayRx: trafficTracker.todayRx,
                              todayTx: trafficTracker.todayTx,
                              dailyBars: bars)
        PanelOpenProbe.mark("B3.3 updateProcesses")
#if DEBUG
        content.updateProcesses(forceEmptyDataForEvidence ? [] : processMonitor.processSpeeds)
#else
        content.updateProcesses(processMonitor.processSpeeds)
#endif
        PanelOpenProbe.mark("B3.4 launchAtStartup")
        content.launchAtStartupEnabled = isLaunchAtStartupSaved
        // 额度：中频分支 5 秒调用一次，monitor 内部 60 秒节流，不会打满 provider 限流
        PanelOpenProbe.mark("B3.5 billing(中频)")
        billingMonitor?.refresh()
    }

    /// 按内容自适应高度（≤ 520pt），高度变化时才调整 popover
    ///
    /// 内容高于 520pt 时不做硬截断：面板内部 NSScrollView 转为垂直滚动（隐式滚动条），
    /// 因此进程数变多 / 字体放大 / 多语言换行时仍能看到全部内容。
    func updateContentSize(force: Bool = false) {
        // 批处理期间只记账：整段刷新结束时统一算一次（避免每步都全树布局）
        guard contentBatchDepth == 0 else {
            contentBatchNeedsForceSize = contentBatchNeedsForceSize || force
            return
        }
        PanelOpenProbe.bucket("updateContentSize") {
            // desiredContentHeight 内部已先 layoutSubtreeIfNeeded，这里不重复跑一遍整树布局
            let needed = PanelOpenProbe.bucket("desiredContentHeight") { content.desiredContentHeight }
            let height = min(max(needed, 180), MenuPanelStyle.maxHeight)
            guard force || abs(popover.contentSize.height - height) > 0.5 else { return }
            PanelOpenProbe.bucket("popover.contentSize 赋值") {
                popover.contentSize = NSSize(width: MenuPanelStyle.panelWidth, height: height)
            }
        }
    }

    /// 开始内容更新批处理（嵌套可重入，最外层结束时统一重算一次尺寸）
    func beginContentBatch() {
        contentBatchDepth += 1
    }

    /// 结束内容更新批处理：最外层结束时按记账结果补一次尺寸重算
    func endContentBatch() {
        contentBatchDepth = max(0, contentBatchDepth - 1)
        guard contentBatchDepth == 0 else { return }
        let force = contentBatchNeedsForceSize
        contentBatchNeedsForceSize = false
        updateContentSize(force: force)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        // 收起后清空键盘焦点，下次展开从第一行开始
        content.resetKeyboardFocus()
    }
}

#if DEBUG

// MARK: - 取证与测量钩子（仅 DEBUG）

extension MenuPanelController {

    /// 取证专用（仅 DEBUG）：强制 popover 内容与窗口外观（真实窗口渲染，非离屏缓存）
    func forceAppearanceForEvidence(_ name: NSAppearance.Name) {
        guard let appearance = NSAppearance(named: name) else { return }
        NSApp.appearance = appearance
        content.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
    }

    /// 取证专用（仅 DEBUG）：切换展示分页
    func selectTabForEvidence(_ tab: MenuPanelTab) {
        content.select(tab: tab)
        updateContentSize(force: true)
    }

    /// 取证专用（仅 DEBUG）：popover 真实窗口号与 frame（供 screencapture -l 用）
    func evidenceWindow() -> (number: Int, frame: NSRect)? {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return nil }
        return (window.windowNumber, window.frame)
    }

    /// 测量专用（仅 DEBUG）：popover 内容窗口对象（强制首帧落屏用）
    func measurePanelWindow() -> NSWindow? { popover.contentViewController?.view.window }

    /// 取证专用（仅 DEBUG）：当前分页
    var currentTabForEvidence: MenuPanelTab { content.currentTab }

    /// 取证专用（仅 DEBUG）：分段条当前可见分页（隐藏分页后应少一段）
    var visibleTabsForEvidence: [MenuPanelTab] { content.tabBar.visibleTabs }

    /// 取证专用（仅 DEBUG）：系统页二级详情是否展开
    var systemDetailShownForEvidence: Bool { content.systemPane.isShowingDetail }

    /// 取证专用（仅 DEBUG）：进入系统页二级详情（CPU），用于验证隐藏分页时详情收起
    func showSystemDetailForEvidence() {
        content.select(tab: .system)
        content.systemPane.showDetail(.cpu)
        updateContentSize(force: true)
    }
}

#endif
