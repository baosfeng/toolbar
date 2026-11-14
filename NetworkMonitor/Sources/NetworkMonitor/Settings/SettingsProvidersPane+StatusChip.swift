import AppKit
import NetworkMonitorUI

// MARK: - 额度 Provider 设置页（页头状态胶囊）

/// 页头状态胶囊 —— 从主文件拆出，守住单文件 15 KiB 门禁
///
/// 纯函数：只吃四个读数、不碰 monitor。页内每秒的倒计时 tick 都会走到 `refresh()`，
/// 因此这里不能有任何额外 I/O（不查凭据存储、不扫目录）。
extension SettingsProvidersPane {

    /// 页头胶囊：一个主语（几个实例）+ 一个状态（查询态）
    ///
    /// 文案沿用面板额度卡同一套词（正常 / 未刷新 / 查询中），避免设置页说「就绪」、
    /// 面板说「正常」这种两套说法。一个凭据都没配置时返回 nil：
    /// 没有可陈述的查询状态，挂空胶囊只是噪音。
    static func statusChip(enabledConfigured: Int,
                           configuredTotal: Int,
                           anyLoading: Bool,
                           allRefreshed: Bool) -> SettingsStatusChip? {
        guard configuredTotal > 0 else { return nil }
        guard enabledConfigured > 0 else {
            // 有凭据但全部关掉了：主语仍是「已配置的实例数」，状态是停用
            return SettingsStatusChip(subject: "\(configuredTotal) 个已配置", detail: "已停用", tone: .muted)
        }
        if anyLoading {
            return SettingsStatusChip(subject: "\(enabledConfigured) 个已配置", detail: "查询中", tone: .ok)
        }
        return SettingsStatusChip(subject: "\(enabledConfigured) 个已配置",
                                  detail: allRefreshed ? "正常" : "未刷新",
                                  tone: allRefreshed ? .ok : .muted)
    }
}
