import AppKit
import NetworkMonitorUI

// MARK: - 局域网互传设置页（页头状态胶囊）

/// 页头状态胶囊 —— 从主文件拆出，守住单文件 15 KiB 门禁
///
/// 跨文件访问：`refreshStatusChip()` 由 private 放宽为 internal，仅供主文件的
/// `refresh()` 调用。
extension SettingsTransferPane {

    /// 页头胶囊：局域网里在线设备数
    ///
    /// 为什么没有契约里的「可接收」主语：服务的监听态（`TransferService.isRunning`）在 actor 内，
    /// App 层只能 `await`；而页头是同步刷新的，await 回来的是上一帧的值（首帧为空），
    /// 拿它拼胶囊等于先显示一个假状态。这里只用同步可得的真实读数（设备表快照），
    /// 监听态要不要接需要 Core 侧提供一个 nonisolated 访问器。
    func refreshStatusChip() {
        let online = service.deviceSnapshot().filter(\.isOnline).count
        page.setStatusChip(SettingsStatusChip(subject: "\(online) 台在线",
                                              tone: online > 0 ? .ok : .muted))
    }
}
