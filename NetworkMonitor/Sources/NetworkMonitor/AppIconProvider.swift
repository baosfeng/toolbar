import AppKit
import Darwin

// MARK: - 进程 App 图标解析

/// 进程 App 图标解析 — 优先按 PID 反查进程所属应用包，再退化为按进程名匹配
///
/// nettop 给出的进程名常被截断（如 DeepSeek Harnes）或只是可执行名（如 mDNSResponder），
/// 单靠名字查 bundleID 多数场景查不到，因此主路径是 PID：
/// 1. NSRunningApplication(processIdentifier:) 取所属 App 的 bundle
/// 2. proc_pidpath 取可执行文件绝对路径，向上找 .app 包（覆盖 Electron Helper 子进程）
/// 3. 非 App 的系统可执行文件，直接取该路径的系统图标
/// 4. 最后才按名字查 bundleID（兼容无 PID 的快照与测试数据）
@MainActor
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

    /// 图标缓存：键含 PID + 进程名，避免 PID 回收后串图标；到上限整体清空，保持有界
    private static var iconCache: [String: NSImage] = [:]

    /// 缓存条数上限
    private static let iconCacheLimit = 128

    /// 解析进程对应的应用包路径（找不到返回 nil）
    ///
    /// - Parameters:
    ///   - name: nettop 给出的进程名
    ///   - pid: 进程 PID（<= 0 表示未知，退化为纯名字匹配）
    static func applicationURL(forProcess name: String, pid: Int32 = 0) -> URL? {
        // 1. 进程所属 App 的 bundle（最准，覆盖截断名）
        if pid > 0, let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL {
            return bundleURL
        }
        // 2. 可执行路径向上找 .app（覆盖 Electron Helper 这类无独立 bundle 的子进程）
        if let path = executablePath(pid: pid),
           let bundleURL = enclosingBundleURL(forExecutablePath: path) {
            return bundleURL
        }
        // 3. 名字直查 bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            return url
        }
        // 4. 常见进程名映射
        guard let bundleID = bundleIDMap[name] else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// 取真实 App 图标（尺寸固定，供菜单项 / 面板行复用；取不到返回 nil）
    ///
    /// - Parameters:
    ///   - name: nettop 给出的进程名
    ///   - pid: 进程 PID（<= 0 表示未知）
    ///   - size: 期望边长（point）
    static func icon(forProcess name: String, pid: Int32 = 0, size: CGFloat) -> NSImage? {
        let key = String(pid) + "|" + name + "|" + String(Int(size))
        if let cached = iconCache[key] { return cached }
        guard let image = resolveIcon(name: name, pid: pid, size: size) else { return nil }
        if iconCache.count >= iconCacheLimit { iconCache.removeAll(keepingCapacity: true) }
        iconCache[key] = image
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

    // MARK: - 私有解析

    /// 实际解析图标：应用包 → 可执行路径 → nil
    private static func resolveIcon(name: String, pid: Int32, size: CGFloat) -> NSImage? {
        if let url = applicationURL(forProcess: name, pid: pid) {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: size, height: size)
            return image
        }
        // 非 App 的系统可执行文件（如 mDNSResponder）按其路径取系统图标，
        // 这比虚线占位更容易辨认进程身份
        if let path = executablePath(pid: pid) {
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: size, height: size)
            return image
        }
        return nil
    }

    /// 取进程可执行文件绝对路径（proc_pidpath；失败返回 nil）
    private static func executablePath(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// 从可执行文件路径向上找到所属 .app 包（没有返回 nil）
    private static func enclosingBundleURL(forExecutablePath path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        // 从可执行文件本身开始向上，最多回溯 6 层（Helper 位于 .app/Contents/Frameworks/... 下）
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app" { return url }
        }
        return nil
    }
}
