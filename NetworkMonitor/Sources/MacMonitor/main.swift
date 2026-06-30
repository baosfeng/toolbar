import AppKit

/// macMonitor 入口点
/// 以辅助工具模式运行，隐藏 Dock 图标，仅显示菜单栏
@MainActor
func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

main()
