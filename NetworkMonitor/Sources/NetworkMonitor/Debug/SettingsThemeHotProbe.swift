#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 主题热切换探针（仅 DEBUG）

/// 验证「换主题 → 设置窗口立刻重绘」这条链路真的接通
///
/// 为什么需要它：离屏快照每次都会强制重绘，**无论有没有订阅事件都会出新颜色**，
/// 所以三主题快照只能证明「令牌随主题走」，证明不了「用户在设置页切主题后窗口自己刷新」。
/// 这里用绘制计数自证：在窗口根视图上挂一个只计数的透明图层，先清账，
/// 再走真实事件链路（AppEvents.postAppearanceChanged），看它是否被重新绘制。
///
/// 触发：NM_THEME_HOT_PROBE=<输出目录> <bundle 内可执行>
@MainActor
enum SettingsThemeHotProbe {

    static let envKey = "NM_THEME_HOT_PROBE"

    /// 入口：环境变量存在时跑探针并退出进程
    static func runIfRequested(settings: SettingsWindow?) {
        guard let path = ProcessInfo.processInfo.environment[envKey], !path.isEmpty else { return }
        guard let settings else {
            AppContext.shared.logger.error("热切换探针缺少设置窗口")
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await probe(settings: settings, directory: directory)
            NSApp.terminate(nil)
        }
    }

    private static func probe(settings: SettingsWindow, directory: URL) async {
        settings.select(.general)
        settings.window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 250_000_000)

        guard let root = settings.window.contentView else { return }
        let counter = SettingsDrawCounterView(frame: root.bounds)
        counter.autoresizingMask = [.width, .height]
        root.addSubview(counter)
        root.layoutSubtreeIfNeeded()

        for theme in ThemeID.allCases {
            ThemeStyle.apply(theme: ThemeCatalog.theme(for: theme),
                             glassEnabled: false,
                             profile: RenderTierLogic.standard)
            // 清账：先把待绘制全部消费掉，计数归零
            root.displayIfNeeded()
            let before = counter.drawCount

            // 走真实链路：设置页写偏好后发的就是这条通知
            AppEvents.postAppearanceChanged()
            try? await Task.sleep(nanoseconds: 250_000_000)
            root.displayIfNeeded()

            let redrawn = counter.drawCount - before
            print("热切换探针：[" + theme.displayName + "] 事件后重绘次数=" + String(redrawn))
        }

        // 离屏图放在循环之后：render 会把根视图借到临时窗口里
        counter.removeFromSuperview()
        root.displayIfNeeded()
        let url = directory.appendingPathComponent("settings-hot-final.png")
        MenuPanelSnapshot.render(view: root, size: SettingsTheme.windowSize,
                                 appearanceName: .aqua, to: url)
    }
}

/// 只统计 draw 调用次数的透明图层 —— 不画任何东西，只作为「有没有重绘」的证据
private final class SettingsDrawCounterView: NSView {
    private(set) var drawCount = 0

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
    }
}
#endif
