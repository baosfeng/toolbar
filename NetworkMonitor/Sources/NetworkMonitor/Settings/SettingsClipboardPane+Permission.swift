import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板设置页（页头状态胶囊）

/// 页头胶囊与权限卡的接线 — 从主文件拆出：主文件要腾出空间放「存储」卡
///
/// 口径收敛：状态一律读 `permissions.snapshot`（`SystemPermissionCenter` 的统一快照），
/// 本页不再调 AXIsProcessTrusted / CGPreflight / NSPasteboard.accessBehavior。
/// 刷新时机由权限链统一驱动（应用激活、面板打开、卡头「检测状态」），
/// 所以用户从系统设置勾选回来、切回本应用时状态灯立即变绿，不必重启。
///
/// 跨文件访问：`lastStorageUsage` / `permissionCard` 与 `permissions` 由 private 放宽为
/// internal，仅供本扩展与页面 refresh 使用。
extension SettingsClipboardPane {

    /// 页头胶囊：三类权限合计授权态 + 图片文件数（与权限卡、存储卡同一份读数）
    ///
    /// 文件数只在存储卡刷新时传进来一次，之后权限刷新复用 —— 两处各扫一遍目录没有意义。
    func refreshHeaderChip(usage: ClipboardStorageUsage.Summary? = nil) {
        if let usage { lastStorageUsage = usage }
        let snapshot = permissions.snapshot
        page.setStatusChip(SettingsStatusChip(subject: snapshot.summaryLabel,
                                              detail: lastStorageUsage.map { "\($0.fileCount) 个文件" },
                                              tone: snapshot.summaryTone))
    }

    /// 权限侧刷新：重读快照（权限卡通过订阅自行重绘）+ 同步页头胶囊
    ///
    /// 卡片不在这里手动重绘：`permissions.refresh()` 会把新快照推给所有订阅者，
    /// 由卡片自己决定怎么画。
    func refreshPermissionChip() {
        permissions.refresh()
        refreshHeaderChip()
    }
}
