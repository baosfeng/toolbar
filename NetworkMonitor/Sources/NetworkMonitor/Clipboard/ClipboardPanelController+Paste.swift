import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 粘贴与复制

/// 面板的「选中项 → 系统剪贴板 → 目标 App」这一条出口
///
/// 拆出原因：ClipboardPanelController 主文件已到 15 KiB 单文件门禁；粘贴的时序约束
/// （收起面板 → 目标 App 回前台 → 合成按键）自成一段，放在主文件里和生命周期混在一起看不清。
extension ClipboardPanelController {

    /// 粘贴选中条目
    ///
    /// 时序：收起面板让出 key → 把目标 App 拉回前台 → 写剪贴板 → 等前台切换完成 → 合成 ⌘V。
    func pasteSelected(asPlainText: Bool) {
        guard let item = selectedItem else { return }
        if paster.hasTargetApplication {
            let targetBundleID = paster.targetBundleID
            hide(animated: false)
            // 只 orderOut 不够：本 App 仍是 active，合成的 ⌘V 会落回自己（没有窗口可接，直接丢失），
            // 用户表现为「点了没粘上，再按一次 ⌘V 才行」。这里把目标 App 拉回前台，
            // 具体的前台切换由 ClipboardPaster 轮询确认后再发按键。
            if let targetBundleID,
               let target = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first {
                target.activate(options: [])
            }
        }
        paster.paste(item, asPlainText: asPlainText) { [weak self] outcome in
            self?.reportPasteOutcome(outcome)
        }
    }

    /// 仅复制（不合成按键）
    func copySelected() {
        guard let item = selectedItem else { return }
        reportCopyOutcome(paster.copyOnly(item))
    }
}
