import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 截图前台协调唯一出口

/// 截图链路的「抢前台」与「归还菜单栏态」的唯一出口
///
/// 只做两件事，且都**不切换激活策略**：
/// - `claimForeground()`：`activate` + 让覆盖层成为 key window；
/// - `restoreMenuBar()`：确保 App 回到 `.accessory`（兜底，正常路径下已经是）。
///
/// 为什么不切 `.regular`：`.regular` 的可见后果就是 Dock 里多一个图标。
/// 截图需要的是「覆盖层收到键盘」，而 `.nonactivatingPanel` + `canBecomeKey`
/// 本身就能让面板成为 key window 收键（贴图窗 `PinWindow` 一直是这个形态），
/// 与「App 是不是可激活前台应用」无关。历史实现切 `.regular` 是为了让系统把
/// 键盘归属交过来，代价是每次截图 Dock 都闪一下；本文件把这个代价去掉。
///
/// 单出口的意义：策略只能从 `restoreMenuBar()` 归位，任何新分支都走这一条，
/// 不会再出现「某条路径漏了切回」——那种漏法编译与功能测试都发现不了，
/// 只有用户看见 Dock 图标。守卫测试会拦住别处直接写 `setActivationPolicy(.regular)`。
@MainActor
enum SnipForegroundPolicy {

    /// 策略采样（仅 DEBUG 探针使用；Release 下不收集，避免白占内存）
    private(set) static var samples: [SnipPolicySample] = []

    /// 当前是否仍是菜单栏态
    static var isMenuBar: Bool { NSApp.activationPolicy() == .accessory }

    /// 记录一次采样（探针与审计共用同一份口径）
    static func record(_ phase: SnipPolicyPhase) {
        #if DEBUG
        samples.append(SnipPolicySample(phase: phase, isAccessory: isMenuBar))
        #endif
    }

    /// 清空采样（每次探针流程开始前调用）
    static func resetSamples() {
        samples.removeAll()
    }

    /// 抢前台：只激活 + 让覆盖层成为 key，不改激活策略（改策略就会出 Dock 图标）
    static func claimForeground() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 归位：确保 App 回到菜单栏态
    ///
    /// 保留这一步是**兜底**而不是主路径：正常流程从不借出 `.regular`，
    /// 但外部（系统、其它模块）仍可能把策略改掉，退出截图态必须保证最终是菜单栏 App。
    static func restoreMenuBar() {
        guard NSApp.activationPolicy() != .accessory else { return }
        AppContext.shared.logger.warning("截图收尾发现激活策略不是菜单栏态，已归位")
        NSApp.setActivationPolicy(.accessory)
    }
}
