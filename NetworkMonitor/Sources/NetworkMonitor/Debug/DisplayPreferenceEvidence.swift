#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 显示偏好生效取证（仅 DEBUG）

/// 菜单栏显示偏好与面板分页偏好的「真的生效了」取证钩子 — **仅 DEBUG 编译**
///
/// 设置页写的三个死设置（布局 / 单位 / 刷新周期）以前没有任何消费方，跑起来改设置看不出反应。
/// 这里用同一条真实链路（写偏好 → 发事件 → MenuBarManager / MenuPanelView 订阅）验证效果：
/// - `NM_DISPLAY_EVIDENCE=1`：启动 1.4s 后依次切两行布局、全称单位、5 秒周期，各记一行状态栏文本与
///   当前定时器周期；再隐藏「系统」分页，记当前分页与系统页二级详情状态；最后把偏好还原。
/// - `NM_EVIDENCE_SUITE=<suite>`：偏好写隔离 suite（由 MenuBarManager.preferredStorage 读取），
///   不污染用户真实设置。
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
                         metrics: prefs.enabledMetrics, visible: tabPrefs.visibleTabs)

        var lines: [String] = []
        lines.append("# 菜单栏显示偏好生效取证")

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

        // 5) 分页可见性：打开系统页 → 进二级详情 → 隐藏系统分页
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

        // 6) 还原偏好（恢复默认「单行 / 紧凑 / 1 秒 / 全部分页可见」）
        prefs.layout = originals.layout
        prefs.unitStyle = originals.unit
        prefs.refreshInterval = originals.interval
        tabPrefs.visibleTabs = originals.visible
        AppEvents.postMenuBarDisplayChanged()
        AppEvents.postPanelTabsChanged()
        logger.info("显示偏好取证完成")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - 输出

    /// 周期格式化（保留一位小数，便于看出 1 秒 / 5 秒切换）
    private static func fmt(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", interval)
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
