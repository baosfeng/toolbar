import AppKit

#if DEBUG

// MARK: - 取证与测量钩子（仅 DEBUG）

/// 从主文件拆出的调试入口：取证 / 测量都走与真实点击相同的路径，
/// 但不参与生产构建（整个文件在 #if DEBUG 内）。
///
/// 拆分理由：MenuBarManager.swift 撞到单文件 15 KiB 上限，
/// 这两组钩子是纯调试职责，与「状态栏 + 定时器」核心职责无关。
extension MenuBarManager {

    /// 取证专用（仅 DEBUG）：走与点击状态栏完全相同的 toggle 路径打开面板
    func openPanelForEvidence() {
        togglePanel()
    }

    /// 取证专用（仅 DEBUG）：popover 窗口号与 frame
    func evidenceWindow() -> (number: Int, frame: NSRect)? {
        panel.evidenceWindow()
    }

    /// 取证专用（仅 DEBUG）：强制 popover 外观（浅色/深色）
    func forceAppearanceForEvidence(_ name: NSAppearance.Name) {
        panel.forceAppearanceForEvidence(name)
    }

    /// 取证专用（仅 DEBUG）：切换到指定分页
    func selectTabForEvidence(_ tab: MenuPanelTab) {
        panel.selectTabForEvidence(tab)
    }

    /// 取证专用（仅 DEBUG）：强制空态（进程 / 剪贴板）
    func forceEmptyForEvidence() {
        panel.forceEmptyDataForEvidence = true
    }

    /// 取证专用（仅 DEBUG）：状态栏当前文本（含换行，可直接核对 layout / 单位写法）
    var statusTitleForEvidence: String { statusItem.button?.attributedTitle.string ?? "" }

    /// 取证专用（仅 DEBUG）：当前定时器周期（核对「间隔」偏好是否真的重建了定时器）
    var timerIntervalForEvidence: TimeInterval { timerInterval }

    /// 取证专用（仅 DEBUG）：面板当前分页
    var currentTabForEvidence: MenuPanelTab { panel.currentTabForEvidence }

    /// 取证专用（仅 DEBUG）：分段条可见分页
    var visibleTabsForEvidence: [MenuPanelTab] { panel.visibleTabsForEvidence }

    /// 取证专用（仅 DEBUG）：系统页二级详情是否展开
    var systemDetailShownForEvidence: Bool { panel.systemDetailShownForEvidence }

    /// 取证专用（仅 DEBUG）：进入系统页二级详情
    func showSystemDetailForEvidence() {
        panel.showSystemDetailForEvidence()
    }

    /// 取证专用（仅 DEBUG）：跑显示偏好生效取证（见 Debug/DisplayPreferenceEvidence.swift）
    func runStatusEvidenceIfRequested() {
        guard !PanelOpenProbe.requested else { return }
        DisplayPreferenceEvidence.runIfRequested(manager: self)
    }

    /// 测量专用（仅 DEBUG）：面板当前是否展开
    var isPanelShownForMeasure: Bool { panel.isShown }

    /// 测量专用（仅 DEBUG）：收起面板（关掉上一轮，准备下一次测量）
    func closePanelForMeasure() {
        panel.close()
    }

    /// 测量专用（仅 DEBUG）：popover 内容窗口（强制首帧落屏用）
    func panelWindowForMeasure() -> NSWindow? {
        panel.measurePanelWindow()
    }

    /// 测量专用（仅 DEBUG）：popover 当前内容尺寸（核对高度是否已按内容订好）
    var panelContentSizeForMeasure: NSSize { panel.popover.contentSize }

}

#endif
