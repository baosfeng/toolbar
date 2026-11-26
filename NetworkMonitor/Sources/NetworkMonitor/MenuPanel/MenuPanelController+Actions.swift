import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureBilling
import NetworkMonitorUI
import ServiceManagement

// MARK: - 菜单面板动作（MenuPanelController 扩展）

/// 面板动作与视图委托 — 粘贴、剪贴板入口、开机自启动切换，以及 `MenuPanelViewDelegate` 实现。
///
/// 拆出原因：`MenuPanelController` 主体超过单文件 15 KiB 上限，按「主类 + 动作扩展」范式分离。
/// 由主文件 `wireActions()` 调用的动作方法声明为 internal（原 private），
/// 供同模块的 `MenuPanelController.swift` 跨文件装配；同目录内无其他调用方。
extension MenuPanelController: MenuPanelViewDelegate {

    // MARK: - 动作
    //
    // 以下成员（`paste` / `requestSettings` / `requestClipboardHistory` /
    // `toggleLaunchAtStartup` / `isLaunchAtStartupSaved`）由主文件 `wireActions()` 与中频刷新读取
    // 与中频刷新读取，故由 private 放宽为 internal。

    /// 点击条目：收起面板后走与剪贴板面板一致的粘贴路径
    func paste(_ item: ClipboardItem) {
        close()
        // 面板展开时本 App 会被激活；收起后先把目标 App 拉回前台，
        // 否则合成的 ⌘V 会落回自己（只写剪贴板却不粘贴）。
        if let bundleID = paster.targetBundleID,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            target.activate(options: [])
        }
        paster.paste(item, asPlainText: false) { [weak self] outcome in
            let message = outcome.message
            guard let self, !message.isEmpty else { return }
            self.logger.info("菜单面板粘贴：\(message)")
        }
    }

    /// 打开统一设置窗口（可指定分类）
    func requestSettings(section: SettingsSection?) {
        close()
        onOpenSettings?(section)
    }

    func requestClipboardHistory() {
        close()
        onOpenClipboardHistory?()
    }

    /// 开机自启动当前开关态 —— 读系统登记态，与通用页 / 系统权限页同一份判据
    ///
    /// 旧实现读偏好键：注册失败回滚之前，菜单勾选与权限页会显示相反状态。
    var isLaunchAtStartupSaved: Bool {
        launchAtStartupService.isEnabled
    }

    /// 开机自启动切换 — 与设置页共用 `LaunchAtStartupService`，避免两套注册 / 回滚逻辑
    func toggleLaunchAtStartup() {
        let target = !isLaunchAtStartupSaved
        launchAtStartupService.setEnabled(target)
        // 成功失败都按系统登记态重画：失败时服务已回滚偏好，界面不再自己推一套结论
        content.launchAtStartupEnabled = isLaunchAtStartupSaved
        updateContentSize()
    }

    // MARK: - MenuPanelViewDelegate

    func menuPanelViewDidChangeHeight(_ view: MenuPanelView) {
        // 结构变化（切页 / 进出二级详情 / 分段条显隐）：立即重算，不排队
        updateContentSize(force: true)
    }

    func menuPanelViewDidChangeContent(_ view: MenuPanelView) {
        // 数据刷新：高度通常不变，交给签名 + 节流判断（签名不变即零布局）
        updateContentSize()
        // 额度页在内容变化时回拉一次（monitor 内部 60 秒节流）。
        // 必须挡住「由额度推送自己引起的那一次」：推送 → updateBilling → 本回调 → refresh → emit
        // 是同步闭环，空态下每次都 emit 会无限递归直到栈溢出（见 BillingRefreshGate 注释）。
        guard BillingRefreshGate.shouldPullForContentChange(
            isBillingTab: view.currentTab == .credits,
            isPushingSnapshot: billingPushInFlight) else { return }
        billingPushInFlight = true
        defer { billingPushInFlight = false }
        billingMonitor?.refresh()
    }

    func menuPanelViewDidSelectTab(_ view: MenuPanelView) {
        // 懒装配：某页首次切到才进视图树，它的首屏数据要在这一刻补一次，
        // 否则要等下一个刷新节拍（最坏 5 秒）才有内容 —— 表现为「切过去是空的」
        if view.didAssembleCurrentPane {
            refreshPaneFirstDisplay(view.currentTab)
        }
        // 切到 Token 页时按需增量刷新 —— 走新鲜度闸门（60s 内刚扫过就直接复用，
        // 首次装配的那一次已由 firstDisplay → refreshToken 排过，闸门保证不会排第二次）
        if view.currentTab == .token {
            pullTokenIfStale()
        }
        // 切到系统页：立即采一帧再渲染，避免看到上一次打开时的旧值
        if view.currentTab == .system {
            systemMonitor?.poll()
            refreshSystem()
        }
    }

    /// 某分页首次装配后的首屏数据（每页只补一次；之后的刷新仍走常规节拍）
    ///
    /// 懒装配把「建页」与「推数据」拆开了：常规刷新链路只更新已装配页，
    /// 所以首次切页必须在这里把该页该有的数据一次性补齐。
    private func refreshPaneFirstDisplay(_ tab: MenuPanelTab) {
        // 补什么由注册表里该分页的 `firstDisplay` 闭包声明（见 `MenuPanel/PaneModule.swift`）：
        // 加一个分页只加一份声明，这里不再有穷尽 switch。
        guard let module = content.paneModules.module(for: tab),
              let pane = content.paneIfLoaded(tab) else { return }
        module.firstDisplay(self, pane)
    }

    /// 用状态管理器当前快照立即渲染额度页
    ///
    /// 额度是推送式回调（`billingMonitor.onUpdate`）：该页还没装配时收到的推送会被跳过，
    /// 切回来时必须用最后一帧状态补一次，否则要等下一轮刷新（最坏 60 秒节流）。
    // 放宽为 internal：分页注册表的 credits 首屏闭包跨文件调用（见 MenuPanel/PaneModule.swift）
    func renderBillingSnapshot() {
        guard let billingMonitor, !billingPushInFlight else { return }
        billingPushInFlight = true
        defer { billingPushInFlight = false }
        let snapshot = BillingMonitor.Snapshot.make(from: billingMonitor.states,
                                                    enabledProviderCount: billingMonitor.states.count,
                                                    isPaused: billingMonitor.isPaused)
        content.updateBilling(snapshot, notifySize: popover.isShown)
    }

    func menuPanelViewDidRequestClose(_ view: MenuPanelView) {
        close()
    }

    func menuPanelViewDidRequestQuit(_ view: MenuPanelView) {
        NSApplication.shared.terminate(nil)
    }

    func menuPanelViewDidRequestSettings(_ view: MenuPanelView, section: SettingsSection?) {
        requestSettings(section: section)
    }

    func menuPanelViewDidRequestClipboardHistory(_ view: MenuPanelView) {
        requestClipboardHistory()
    }

    func menuPanelViewDidRequestToggleLaunchAtStartup(_ view: MenuPanelView) {
        toggleLaunchAtStartup()
    }

}