import AppKit

// MARK: - 进程 App 图标解析

/// 进程 App 图标解析 — 由进程名反查应用包并取真实图标（`NSWorkspace.icon(forFile:)`）
///
/// nettop 给出的进程名不一定是 bundleID（如 `Google Chrome H`），因此先按名字直查，
/// 再用常见进程名 → bundleID 映射兜底；两者都取不到时返回 nil，由调用方决定占位。
enum AppIconProvider {

    /// 常见进程名 → bundleID 映射（nettop 名字通常是 App 名而非 bundleID）
    private static let bundleIDMap: [String: String] = [
        "Google Chrome": "com.google.Chrome",
        "Safari": "com.apple.Safari",
        "Firefox": "org.mozilla.firefox",
        "iTerm2": "com.googlecode.iterm2",
        "Terminal": "com.apple.Terminal",
        "Finder": "com.apple.Finder",
        "Xcode": "com.apple.dt.Xcode",
        "Slack": "com.tinyspeck.slackmacgap",
        "Spotify": "com.spotify.client",
        "Discord": "com.hnc.Discord",
        "Visual Studio Code": "com.microsoft.VSCode",
        "Code": "com.microsoft.VSCode",
        "VSCode": "com.microsoft.VSCode",
        "QQ": "com.tencent.qq",
        "WeChat": "com.tencent.xinWeChat",
        "Telegram": "ru.keepcoder.Telegram",
        "DingTalk": "com.alibaba.DingTalk",
        "WPS": "com.kingsoft.wpsoffice.mac",
        "Microsoft Word": "com.microsoft.Word",
        "Microsoft Excel": "com.microsoft.Excel",
    ]

    /// 解析进程对应的应用包路径（找不到返回 nil）
    static func applicationURL(forProcess name: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            return url
        }
        guard let bundleID = bundleIDMap[name] else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// 取真实 App 图标（尺寸固定，供菜单项 / 面板行复用；取不到返回 nil）
    static func icon(forProcess name: String, size: CGFloat) -> NSImage? {
        guard let url = applicationURL(forProcess: name) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: size, height: size)
        return image
    }

    /// 灰色占位图标（SF Symbols，模板色跟随语义色；符号缺失时返回 nil）
    static func placeholderIcon(size: CGFloat) -> NSImage? {
        let image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "应用")
            ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: "应用")
        guard let image else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size - 4, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.isTemplate = true
        return configured
    }
}
