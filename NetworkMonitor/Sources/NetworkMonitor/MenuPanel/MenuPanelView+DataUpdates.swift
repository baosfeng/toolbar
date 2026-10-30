import AppKit
import NetworkMonitorCore

// MARK: - 面板数据更新（拆出 MenuPanelView.swift）

/// 各分页的数据更新入口 — 从主文件拆出（主文件贴近单文件 15 KiB 上限）
///
/// 只放「数据 → 视图」转发与由此引起的尺寸通知；切页、键盘与布局仍在主文件。
/// `delegate` 与各 pane 属性本来就对同模块可见，无需放宽访问级别。
extension MenuPanelView {

    /// 实时速率（1 秒）
    func updateSpeeds(down: Double, up: Double, downHistory: [Double], upHistory: [Double]) {
        networkPane.updateSpeeds(down: down, up: up, downHistory: downHistory, upHistory: upHistory)
    }

    /// 今日流量 + 近 6 日柱状图（5 秒）
    func updateTraffic(todayRx: UInt64, todayTx: UInt64,
                       dailyBars: [MenuPanelMetrics.DailyTrafficBar]) {
        networkPane.updateTraffic(todayRx: todayRx, todayTx: todayTx, dailyBars: dailyBars)
        delegate?.menuPanelViewDidChangeContent(self)
    }

    /// 活跃进程 Top5（5 秒）
    func updateProcesses(_ processes: [ProcessNetUsage]) {
        networkPane.updateProcesses(processes)
        delegate?.menuPanelViewDidChangeContent(self)
    }

    /// 剪贴板最近条目（事件驱动 + 打开面板时强制刷新）
    func updateClipboardItems(_ items: [ClipboardItem]) {
        clipboardPane.update(items: items)
        resetKeyboardFocus()
        delegate?.menuPanelViewDidChangeContent(self)
    }

    /// 额度页快照（状态管理器回调）
    func updateBilling(_ snapshot: BillingMonitor.Snapshot, notifySize: Bool = true) {
        billingPane.update(snapshot)
        if notifySize {
            delegate?.menuPanelViewDidChangeContent(self)
        }
    }

    /// Token 页快照（索引事件回调）
    func updateToken(_ snapshot: HarnessUsageSnapshot, notifySize: Bool = true) {
        tokenPane.update(snapshot)
        if notifySize {
            delegate?.menuPanelViewDidChangeContent(self)
        }
    }

    /// 系统页快照（5 秒；nil = 服务未就绪，逐卡显示「—」而不是空白）
    ///
    /// - Parameter notifySize: 面板展开时才重算 popover 高度（收起时只更新数据）
    func updateSystem(_ snapshot: SystemMetricsSnapshot?, notifySize: Bool = true) {
        systemPane.update(snapshot: snapshot)
        if notifySize {
            delegate?.menuPanelViewDidChangeContent(self)
        }
    }
}
