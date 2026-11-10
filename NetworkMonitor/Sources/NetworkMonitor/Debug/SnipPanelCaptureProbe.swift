#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 面板可见性捕获自证（仅 DEBUG）

/// 验证「打开菜单面板后截图，抓到的是面板还是它背后的背景」
///
/// 触发方式：NM_PANEL_CAPTURE_PROBE=1（同时用 NM_SHOW_PANEL=1 打开面板）
/// 产物：/tmp/nm-panel-capture.png
///
/// 背景：用户口径「点开我们的软件，对着详情页截图，截出来是背景」。
/// 原因是抓屏前先把本 App 切成了前台，transient 的 NSPopover 顺势收起，抓到的就是底下的桌面。
/// 该探针把「面板开着时抓一张」钉成可复跑的取证。
@MainActor
enum SnipPanelCaptureProbe {

    static let envKey = "NM_PANEL_CAPTURE_PROBE"
    static let outputPath = "/tmp/nm-panel-capture.png"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    static func run(capture: any SnipCaptureServicing, manager: MenuBarManager?) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            print("probe: 面板展开=\(manager?.isPanelShownForMeasure ?? false)")
            do {
                let result = try await capture.captureAllDisplays()
                guard let image = result.first?.image else {
                    print("probe: 捕获为空")
                    exit(2)
                }
                try SnipDemo.saveImage(image, to: outputPath)
                print("probe: 已写入 \(outputPath)")
            } catch {
                print("probe error: \(error)")
            }
            exit(0)
        }
    }
}
#endif
