#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 显示偏好生效取证（仅 DEBUG）

/// 菜单栏显示偏好与面板分页偏好的「真的生效了」取证钩子 — **仅 DEBUG 编译**
///
/// 设置页写的三个死设置（布局 / 单位 / 刷新周期）以前没有任何消费方，跑起来改设置看不出反应。
/// 这里用同一条真实链路（写偏好 → 发事件 → MenuBarManager / MenuPanelView 订阅）验证效果：
/// - `NM_DISPLAY_EVIDENCE=1`：启动 1.4s 后依次切两行布局、全称单位、**短标签档**、
///   **中文数值单位**、**逐项自定义前缀**、5 秒周期，各记一行状态栏文本与当前定时器周期；
///   再隐藏「系统」分页，记当前分页与系统页二级详情状态；最后把偏好逐项还原。
/// - `NM_EVIDENCE_SUITE=<suite>`：偏好写隔离 suite（由 MenuBarManager.preferredStorage 读取），
///   不污染用户真实设置。
///
/// 指标集合在取证开头被固定为 `↓ ↑ CPU Token今日`：默认只开两个箭头，而箭头两档同形、
/// 速率写法又不随数值单位变——不补这两项，切标签档 / 数值单位的标题会一个字符都不动。
@MainActor
enum DisplayPreferenceEvidence {

    /// 触发开关的环境变量名
    static let enableEnvKey = "NM_DISPLAY_EVIDENCE"
    /// 结论输出文件（默认 /tmp/nm-display-evidence.txt）
    static let outputEnvKey = "NM_DISPLAY_EVIDENCE_FILE"

    private static var logger: LoggingService { AppContext.shared.logger }

    /// 入口：环境变量存在时延时取证并退出进程；未设置时立即返回
    static func runIfRequested(manager: MenuBarManager) {
        guard ProcessInfo.processInfo.environment[enableEnvKey]?.isEmpty == false else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            let report = await capture(manager: manager)
            write(report)
            NSApp.terminate(nil)
        }
    }

    // MARK: - 取证主流程

    private static func capture(manager: MenuBarManager) async -> String {
        let prefs = manager.displayPreferences
        let tabPrefs = PanelTabPreferences(storage: MenuBarManager.preferredStorage())
        // 原始偏好：取证结束后逐项还原
        let originals = (layout: prefs.layout, unit: prefs.unitStyle,
                         interval: prefs.refreshInterval, template: prefs.template,
                         metrics: prefs.enabledMetrics, order: prefs.metricOrder,
                         labelStyle: prefs.labelStyle, numberUnits: manager.numberUnitPreferences.style,
                         visible: tabPrefs.visibleTabs)

        var lines: [String] = []
        lines.append("# 菜单栏显示偏好生效取证")

        // 指标集合先补到能看出差异：默认只开 ↑↓，而箭头符号与速率写法
        // 都不随「标签档 / 数值单位」变化 —— 不补这两项，切档标题一个字符都不动，
        // 取证就会得出「没生效」的假结论。CPU 看标签档、Token 今日看标签 + 计数单位。
        prefs.enabledMetrics = [.downSpeed, .upSpeed, .cpu, .tokenToday]

        // 1) 单行 + 紧凑单位（基线）
        prefs.unitStyle = .short
        prefs.layout = .singleLine
        prefs.refreshInterval = 1
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("singleLine+short   interval=\(fmt(manager.timerIntervalForEvidence))  title=\(quoted(manager.statusTitleForEvidence))")

        // 2) 两行布局
        prefs.layout = .twoLine
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("twoLine+short      interval=\(fmt(manager.timerIntervalForEvidence))  title=\(quoted(manager.statusTitleForEvidence))")

        // 3) 全称单位
        prefs.unitStyle = .full
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("twoLine+full       interval=\(fmt(manager.timerIntervalForEvidence))  title=\(quoted(manager.statusTitleForEvidence))")

        // 4) 5 秒刷新周期：定时器必须真的重建
        prefs.refreshInterval = 5
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("twoLine+full+5s    interval=\(fmt(manager.timerIntervalForEvidence))  title=\(quoted(manager.statusTitleForEvidence))")

        // 5) 标签档：短标签（完整档已在 1–4 里取过）——只有 CPU / Token 这类文字前缀会变，
        //    ↓ / ↑ 两个箭头是符号、两档同形，正是「切了看不出变化」的真实边界
        prefs.unitStyle = .short
        prefs.labelStyle = .short
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("short labels       title=\(quoted(manager.statusTitleForEvidence))")

        // 6) 数值单位：同一份快照切成万 / 亿 —— 计数类（Token 今日）立刻变、速率类不动；
        //    走的是 AppEvents.numberUnitStyleChanged 那条真实链路（MenuBarManager 订阅它）
        manager.numberUnitPreferences.setStyle(.chinese)
        AppEvents.postNumberUnitStyleChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("chinese units      title=\(quoted(manager.statusTitleForEvidence))")

        // 7) 逐项自定义：只覆盖 Token 今日一项，验证「自定义 > 档位」优先级与尾随空格
        prefs.setCustomLabel("TK", for: .tokenToday)
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("custom token       title=\(quoted(manager.statusTitleForEvidence))")
        prefs.resetCustomLabels()

        // 8) 分页可见性：打开系统页 → 进二级详情 → 隐藏系统分页
        manager.selectTabForEvidence(.system)
        try? await Task.sleep(nanoseconds: 300_000_000)
        lines.append("tab=system         current=\(manager.currentTabForEvidence.title)")
        manager.showSystemDetailForEvidence()
        try? await Task.sleep(nanoseconds: 200_000_000)
        lines.append("system.detail=on   isShowingDetail=\(manager.systemDetailShownForEvidence)")

        var visible = tabPrefs.visibleTabs
        visible.remove(.system)
        tabPrefs.visibleTabs = visible
        AppEvents.postPanelTabsChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        let segments = manager.visibleTabsForEvidence.map(\.title).joined(separator: "/")
        lines.append("hidden system      current=\(manager.currentTabForEvidence.title)  isShowingDetail=\(manager.systemDetailShownForEvidence)  segments=[\(segments)]")

        // 9) 菜单栏指标顺序：交换「下载 / 上传」→ 状态栏文本首位变化；再恢复默认
        var swapped = prefs.metricOrder
        if let downIndex = swapped.firstIndex(of: .downSpeed), downIndex + 1 < swapped.count {
            swapped.swapAt(downIndex, downIndex + 1)
        }
        prefs.metricOrder = swapped
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("order swapped      order=\(orderText(prefs.metricOrder))  title=\(quoted(manager.statusTitleForEvidence))")

        prefs.resetMetricOrder()
        AppEvents.postMenuBarDisplayChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)
        lines.append("order reset        order=\(orderText(prefs.metricOrder))  title=\(quoted(manager.statusTitleForEvidence))")

        // 10) 还原偏好：本轮取证改过的每一项都回到取证前的值
        //     （指标集合与标签档是新加的，一起还原；数值单位走 manager 的偏好实例，
        //      与设置页写的是同一个键）
        prefs.layout = originals.layout
        prefs.unitStyle = originals.unit
        prefs.refreshInterval = originals.interval
        prefs.metricOrder = originals.order
        prefs.labelStyle = originals.labelStyle
        prefs.enabledMetrics = originals.metrics
        manager.numberUnitPreferences.setStyle(originals.numberUnits)
        tabPrefs.visibleTabs = originals.visible
        AppEvents.postMenuBarDisplayChanged()
        AppEvents.postNumberUnitStyleChanged()
        AppEvents.postPanelTabsChanged()
        logger.info("显示偏好取证完成")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - 输出

    /// 周期格式化（保留一位小数，便于看出 1 秒 / 5 秒切换）
    private static func fmt(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", interval)
    }

    /// 指标顺序压成一行（便于核对「交换 / 恢复默认」是否真的落到偏好里）
    private static func orderText(_ order: [MenuBarMetric]) -> String {
        order.map(\.rawValue).joined(separator: "/")
    }

    /// 文本加引号并把换行替换成可见标记（一行一条结论，便于核对两行布局）
    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func write(_ report: String) {
        let path = ProcessInfo.processInfo.environment[outputEnvKey] ?? "/tmp/nm-display-evidence.txt"
        do {
            try report.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            logger.info("显示偏好取证写出：\(path)")
        } catch {
            logger.error("显示偏好取证写入失败：\(error.localizedDescription)")
        }
    }
}
#endif
