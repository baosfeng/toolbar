import AppKit
import NetworkMonitorCore

// MARK: - 菜单栏取证入口（仅 DEBUG）

/// 取证 / 测量入口 —— 从 `MenuBarManager` 主文件拆出
///
/// 拆出理由：这批方法只在 DEBUG 下给快照、偏好生效与面板打开耗时测量用，
/// 与菜单栏运行逻辑无关；主文件已到 15 KiB 门禁边缘（本次加外观偏好后超限），
/// 挪走这一整块比继续压缩注释更合理。
#if DEBUG
extension MenuBarManager {

    /// 走与点击状态栏完全相同的 toggle 路径打开面板
    func openPanelForEvidence() {
        togglePanel()
    }

    /// popover 窗口号与 frame
    func evidenceWindow() -> (number: Int, frame: NSRect)? {
        panel.evidenceWindow()
    }

    /// 强制 popover 外观（浅色 / 深色）
    func forceAppearanceForEvidence(_ name: NSAppearance.Name) {
        panel.forceAppearanceForEvidence(name)
    }

    /// 切换到指定分页
    func selectTabForEvidence(_ tab: MenuPanelTab) {
        panel.selectTabForEvidence(tab)
    }

    /// 强制空态（进程 / 剪贴板）
    func forceEmptyForEvidence() {
        panel.forceEmptyDataForEvidence = true
    }

    /// 状态栏当前文本（含换行，可直接核对 layout / 单位写法）
    var statusTitleForEvidence: String { statusItem.button?.attributedTitle.string ?? "" }

    /// 当前定时器周期（核对渲染档是否真的重建了定时器）
    var timerIntervalForEvidence: TimeInterval { timerInterval }

    /// 面板当前分页
    var currentTabForEvidence: MenuPanelTab { panel.currentTabForEvidence }

    /// 分段条可见分页
    var visibleTabsForEvidence: [MenuPanelTab] { panel.visibleTabsForEvidence }

    /// 系统页二级详情是否展开
    var systemDetailShownForEvidence: Bool { panel.systemDetailShownForEvidence }

    /// 进入系统页二级详情
    func showSystemDetailForEvidence() {
        panel.showSystemDetailForEvidence()
    }

    /// 跑显示偏好 / 外观档位生效取证（见 Debug/DisplayPreferenceEvidence.swift）
    func runStatusEvidenceIfRequested() {
        guard !PanelOpenProbe.requested else { return }
        DisplayPreferenceEvidence.runIfRequested(manager: self)
    }

    /// 面板当前是否展开
    var isPanelShownForMeasure: Bool { panel.isShown }

    /// 收起面板（关掉上一轮，准备下一次测量）
    func closePanelForMeasure() {
        panel.close()
    }

    /// popover 内容窗口（强制首帧落屏用）
    func panelWindowForMeasure() -> NSWindow? {
        panel.measurePanelWindow()
    }

    /// popover 当前内容尺寸（核对高度是否已按内容订好）
    var panelContentSizeForMeasure: NSSize { panel.popover.contentSize }

    // MARK: 外观档位自证

    /// 当前生效的主题（核对设置页切主题后令牌层是否真的换过）
    var themeForEvidence: String { ThemeStyle.current.displayName }

    /// 玻璃实际是否生效
    var glassEnabledForEvidence: Bool { ThemeStyle.glassEnabled }

    /// 当前渲染档摘要（读**面板实际生效的档位**，不是偏好里的值——
    /// 两者分叉正是「设置页切了但没生效」的判据）
    var renderTierSummaryForEvidence: String {
        RenderTierLogic.summary(for: panel.currentTierForEvidence)
    }

    /// 动效当前时长表（核对档位是否真的改写了 `MotionKit.durations`）
    var motionDurationsForEvidence: (state: TimeInterval, expand: TimeInterval,
                                     overlay: TimeInterval, close: TimeInterval,
                                     stagger: TimeInterval) {
        let durations = MotionKit.durations
        return (durations.state, durations.expand, durations.overlay,
                durations.close, durations.stagger)
    }

    /// 当前中频刷新间隔（核对切档是否真的改写了 `MenuPanelController.midInterval`）
    var midIntervalForEvidence: TimeInterval { panel.midIntervalForEvidence }

    /// 当前折线采样点上限
    var historyPointsForEvidence: Int { panel.historyPointsForEvidence }

    /// 应用档位 —— 走与生产完全相同的两个消费方（面板节流 + 状态栏定时器），
    /// 只是档位用显式参数而不是偏好，避免取证写脏用户设置
    func applyTierForEvidence(_ tier: RenderTier) {
        panel.applyRenderTier(tier)
        applyDisplayPreferences(tierOverride: tier)
    }

    /// 应用主题 —— 令牌层 + 面板材质 + 重绘，链路与 `applyAppearance()` 一致
    func applyThemeForEvidence(_ theme: ThemeID) {
        let resolved = ThemeCatalog.theme(for: theme)
        ThemeStyle.apply(theme: resolved,
                         glassEnabled: RenderTierLogic.effectiveGlass(
                            override: appearancePreferences.glassOverride,
                            tier: panel.currentTierForEvidence),
                         profile: RenderTierLogic.profile(for: panel.currentTierForEvidence))
        panel.content.refreshBackdrop()
        panel.content.markSubtreeNeedsDisplay()
    }

    /// 面板玻璃结构自证：返回（玻璃层类型名, 圆角, 基色层 alpha, 层级序号）
    ///
    /// 材质改动不能用离屏图定论（模糊由窗口服务器合成，`cacheDisplay` 画不出来），
    /// 结构自证是主判据。
    func backdropStructureForEvidence() -> (glassType: String, cornerRadius: CGFloat,
                                           veilAlpha: CGFloat, glassIsBottom: Bool) {
        panel.backdropStructureForEvidence()
    }
}
#endif
