#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 更新检查探针（仅 DEBUG）

/// 更新检查取证 — 在真实 app 里跑一次检查，打印状态、界面文案、耗时与主线程空档
///
/// 触发：
/// ```
/// NM_UPDATE_PROBE=live  <包内可执行>                              // 真实 GitHub API
/// NM_UPDATE_PROBE=failure NM_UPDATE_PROBE_URL=http://127.0.0.1:9 <可执行>  // 失败路径
/// NM_UPDATE_PROBE=live NM_UPDATE_PROBE_SHOTS=/tmp/shots <可执行>   // 顺便出关于页快照
/// ```
///
/// 打印口径对应验收：状态、四行界面文案（取真实设置页控件）、耗时、
/// 检查期间主线程最大空档（不卡）、窗口清单（不弹窗）。
@MainActor
enum UpdateCheckProbe {

    /// 是否请求取证
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["NM_UPDATE_PROBE"] != nil
    }

    static func runIfRequested(coordinator: AppCoordinator) {
        guard isRequested else { return }
        let environment = ProcessInfo.processInfo.environment
        let mode = environment["NM_UPDATE_PROBE"] ?? "live"
        let shots = environment["NM_UPDATE_PROBE_SHOTS"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        guard let service = coordinator.updateCheck else {
            print("[update-probe] ❌ 更新检查服务未装配")
            exit(1)
        }

        print("[update-probe] mode=\(mode)"
              + " api=\(environment["NM_UPDATE_PROBE_URL"] ?? GitHubUpdateChecker.defaultBaseURL.absoluteString)"
              + " userAgent=\(AppCoordinator.updateUserAgent)"
              + " current=\(service.currentVersionText)"
              + " lastCheckAt=\(service.lastCheckAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")

        Task { @MainActor in
            // 先等启动期（数据库 / 面板预热 / 索引）过去：要测的是「检查本身卡不卡主线程」，
            // 和启动初始化叠在一起测出来的空档会把启动开销算到检查头上
            try? await Task.sleep(for: .seconds(2))
            print("[update-probe] 检查前窗口数=\(NSApp.windows.count)")
            let ticker = MainThreadGapTicker()
            ticker.start()
            let started = Date()
            let state = await service.runCheck()
            let elapsed = Date().timeIntervalSince(started)
            ticker.stop()

            let presentation = UpdateCheckText.presentation(for: state,
                                                            lastCheckAt: service.lastCheckAt)
            print("[update-probe] state=\(state)")
            print("[update-probe] elapsed=\(String(format: "%.3f", elapsed))s")
            print("[update-probe] 最新版本=\(presentation.latestVersionText)"
                  + " | 状态=\(presentation.statusText)"
                  + " | 说明=\(presentation.notesText)"
                  + " | 按钮=\(presentation.checkButtonTitle)"
                  + " | 可点=\(presentation.canCheck)")
            print("[update-probe] 主线程最大空档=\(String(format: "%.1f", ticker.maxGap * 1000))ms")
            print("[update-probe] 检查后窗口数=\(NSApp.windows.count)"
                  + " 窗口=\(NSApp.windows.map { $0.title.isEmpty ? "<无标题>" : $0.title })")
            print("[update-probe] releasePage=\(service.releasePageURL?.absoluteString ?? "nil")")

            // 界面真值：走真实设置窗口的「关于」页，读控件上的可见文案与按钮无障碍信息
            if let settings = coordinator.settingsWindow {
                // 先真实显示「关于」页：离屏视图上 AppKit 的无障碍属性是惰性的
                // （未上屏时 role 查出来是 AXUnknown），要读屏真值必须先上屏
                settings.show(section: .about)
                try? await Task.sleep(for: .milliseconds(400))
                _ = settings.prepareForSnapshot(.about)
                if let about = settings.currentPaneForSnapshot as? SettingsAboutPane {
                    about.refresh()
                    about.debugLogUpdateSection(mode)
                    if mode == "live" {
                        // 从无障碍层按一次：证明新增按钮的 press 动作真的接在 action 上
                        about.debugPerformAccessibilityPress()
                        try? await Task.sleep(for: .milliseconds(200))
                        print("[update-probe][\(mode)] press 后 state=\(service.state)")
                    }
                }
                if let shots {
                    try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
                    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                        let suffix = appearance == .aqua ? "light" : "dark"
                        guard let view = settings.prepareForSnapshot(.about) else { continue }
                        MenuPanelSnapshot.render(
                            view: view,
                            size: SettingsTheme.windowSize,
                            appearanceName: appearance,
                            to: shots.appendingPathComponent("settings-about-update-\(suffix).png"))
                    }
                    // 内容超过一屏：再出一张滚到底的图，证明会话卡没有被挤丢
                    if let scrolled = settings.prepareForSnapshotScrolledToBottom(.about) {
                        MenuPanelSnapshot.render(
                            view: scrolled,
                            size: SettingsTheme.windowSize,
                            appearanceName: .aqua,
                            to: shots.appendingPathComponent("settings-about-update-scrolled-light.png"))
                    }
                    print("[update-probe] 快照目录=\(shots.path)")
                }
            }
            exit(0)
        }
    }
}

// MARK: - 主线程节拍

/// 主线程空档计时盒（Timer 闭包在主 runloop 上跑，值只在主线程读写）
private final class MainThreadGapBox: @unchecked Sendable {
    var last = Date()
    var maxGap: TimeInterval = 0
}

/// 主线程空档节拍器 — 检查在途期间每 20ms 打一拍，记录最大空档
///
/// 用来证明更新检查是 async 网络等待，没有同步 I/O 卡住主线程（界面不卡）。
@MainActor
private final class MainThreadGapTicker {
    private let box = MainThreadGapBox()
    private var timer: Timer?

    var maxGap: TimeInterval { box.maxGap }

    func start() {
        // 局部常量给闭包捕获：Timer 的 block 是 @Sendable，捕获 @MainActor 属性要显式 self，
        // 捕获这层不变的盒子（@unchecked Sendable）则不需要
        let box = self.box
        box.last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = Date()
                box.maxGap = max(box.maxGap, now.timeIntervalSince(box.last))
                box.last = now
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
