import Foundation

// MARK: - 窗口悬停标签

/// 截图覆盖层的「悬停窗口」标签文案 — 纯格式化，便于单测
///
/// 放在 NetworkMonitorUI：本目标不依赖 AppKit 也不依赖 NetworkMonitorCore，
/// 所以入参只收基础类型（层级数值 + 应用名 + 标题），不接收 Core 的 SnipWindowInfo。
/// 层级数值必须与 Core 的 SnipWindowLayer 白名单一致；TestRunner 里有断言把两者钉在一起，
/// 将来白名单改了而这里没跟，测试会直接红。
public enum SnipWindowLabel {

    /// 普通应用窗口层级
    public static let normalLayer: Int = 0
    /// 程序坞（Dock）层级 — CGWindowList 里是一个整屏窗口，不是逐个图标
    public static let dockLayer: Int = 20
    /// 菜单栏层级 — CGWindowList 里是整条菜单栏，不是逐个菜单项
    public static let menuBarLayer: Int = 24
    /// 状态栏项（含菜单栏 App 的 popover）层级
    public static let statusItemLayer: Int = 25

    /// 层级对应的中文名；非系统层级返回 nil（普通窗口不带层级前缀）
    public static func layerName(_ layer: Int) -> String? {
        switch layer {
        case menuBarLayer: return "菜单栏"
        case dockLayer: return "程序坞"
        case statusItemLayer: return "状态栏项"
        default: return nil
        }
    }

    /// 悬停标签文案
    ///
    /// - 系统层级：有应用名写「菜单栏 — SystemUIServer」，没有就只写「菜单栏」
    /// - 普通窗口：有标题写「应用名 — 标题」，没标题只写应用名，两者都缺写「窗口」
    ///   （空标签会让用户不知道框到了什么）
    public static func text(layer: Int, ownerName: String, title: String) -> String {
        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = layerName(layer) {
            // 程序坞的 ownerName 实测就是「程序坞」，与层级名重复时只写一份，
            // 否则标签读起来是「程序坞 — 程序坞」
            return owner.isEmpty || owner == name ? name : "\(name) — \(owner)"
        }
        let windowTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !windowTitle.isEmpty {
            return owner.isEmpty ? windowTitle : "\(owner) — \(windowTitle)"
        }
        return owner.isEmpty ? "窗口" : owner
    }
}
