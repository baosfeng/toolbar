import AppKit
import CoreWLAN

// MARK: - 系统信息

/// 系统信息读取 — Wi-Fi 名称等 CoreWLAN 侧取值（IP 复用 Core 的 `getLocalIPAddress`）
enum SystemInfoProvider {

    /// Wi-Fi 展示文案
    ///
    /// macOS 14+ 未授权定位时系统会返回空 SSID，此时明确显示「无权限读取」而不是谎报「未连接」；
    /// 权限引导入口在剪贴板设置窗，面板保持只读展示。
    static func wifiDisplayName() -> String {
        guard let interface = CWWiFiClient.shared().interface() else { return "未连接" }
        guard interface.powerOn() else { return "已关闭" }
        guard let ssid = interface.ssid(), !ssid.isEmpty else { return "无权限读取" }
        return ssid
    }
}
