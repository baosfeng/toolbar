import AppKit
import NetworkMonitorCore

// MARK: - 传送页渲染（含签名早退与可见性门控）

/// 面板渲染从主文件拆出：TransferController.swift 已到单文件字节上限。
///
/// 三道闸门（实测依据见 docs/调研/性能剖析-CPU与内存.md）：
/// 1. 数据签名没变 → 直接返回，稳态下每秒定时器零 UI 操作；
/// 2. 面板收起 → 只记账 pendingVisibleRender，不推视图；
/// 3. 面板可见 → 推给视图；倒计时项变化时由 PaneStateBandView 只改那一个 label。
extension TransferController {

    /// 渲染面板（1 秒定时器与各事件回调共用）
    func render(force: Bool = false) {
        let windowActive = preferences.isWindowActive()
        let panelVisible = panel?.isPanelVisible() ?? false
        // 收起时不关心倒计时文本（视图不刷），签名里省掉它：否则每秒都因秒数变化而穿闸
        let autoAcceptText = (windowActive && panelVisible) ? preferences.windowRemainingText() : ""
        let signature = [
            String(devices.count),
            String(sessions.count),
            selectedDeviceId ?? "-",
            statusText,
            autoAcceptText,
            windowActive ? "1" : "0",
        ].joined(separator: "|")
        guard force || signature != renderSignature || (panelVisible && pendingVisibleRender) else { return }
        renderSignature = signature
        guard force || panelVisible else {
            pendingVisibleRender = true
            return
        }
        pendingVisibleRender = false
        panel?.update(devices: devices,
                      sessions: sessions,
                      selectedDeviceId: selectedDeviceId,
                      statusText: statusText,
                      autoAcceptText: windowActive ? preferences.windowRemainingText() : "",
                      autoAcceptActive: windowActive)
    }

    /// 面板刚打开时补推一次（MenuPanelController.refreshAll 调用）：收起期间的数据变化不能漏
    func refreshNow() {
        render(force: true)
    }
}
