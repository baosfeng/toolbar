#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 面板展开过程逐帧轨迹探针（仅 DEBUG）

/// 记录「面板从点击到稳定」每一帧的窗口 frame，用来定位「打开时先居中、随后跳到别处」这类**过程性**抖动
///
/// 触发方式：`NM_PANEL_PIN_TRACE=1 <app 可执行文件>`
///
/// 为什么需要它：`PanelPinProbe` 只在每个分页**稳定之后**采一次 frame，能证明终点一致，
/// 却看不到打开过程中的中间态。用户报的「有的时候点额度 tab 会变到这个位置，刚打开先是居中」，
/// 症状落在**过程**上，只有逐帧轨迹能指认是哪一步在移动。
///
/// 采两段：
/// 1. `attach` 段 —— 面板展开后 1.2 秒，每 16ms 一帧（覆盖出场动画 + 钉住生效）；
/// 2. `switch` 段 —— 切到额度页（最矮的一页，最容易掉位置）后再采 0.9 秒。
///
/// 输出口径：`TRACE t=<毫秒> x= y= w= h=`；探针只如实记录，不自己判合规。
@MainActor
enum PanelPinTraceProbe {

    static let environmentKey = "NM_PANEL_PIN_TRACE"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey]?.isEmpty == false
    }

    /// 帧间隔（秒）—— 60Hz 对齐，足以看清 1~2 帧的跳变
    private static let frameInterval: TimeInterval = 1 / 60.0

    static func run(manager: MenuBarManager) {
        Task { @MainActor in
            // 与 NM_SHOW_PANEL / PanelPinProbe 同一时序约束：晚于 1.2s 预热 + 它的 performClose（toggle 有 0.25s 防抖）
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            print("TRACE_BEGIN")
            manager.openPanelForEvidence()
            await sampleFrames(manager: manager, label: "attach", duration: 1.2)

            manager.selectTabForEvidence(.credits)
            await sampleFrames(manager: manager, label: "switch", duration: 0.9)

            print("TRACE_END")
            exit(0)
        }
    }

    /// 按帧采样并打印（窗口取不到时打 `w=nil`，用来证明「那一刻窗口还没建好」）
    private static func sampleFrames(manager: MenuBarManager, label: String, duration: TimeInterval) async {
        let start = Date()
        var index = 0
        while Date().timeIntervalSince(start) < duration {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if let info = manager.evidenceWindow() {
                let frame = info.frame
                print(String(format: "TRACE %@ t=%d x=%.1f y=%.1f w=%.1f h=%.1f",
                             label, ms, frame.minX, frame.minY, frame.width, frame.height))
            } else {
                print("TRACE \(label) t=\(ms) w=nil")
            }
            index += 1
            try? await Task.sleep(nanoseconds: UInt64(frameInterval * 1_000_000_000))
        }
        print("TRACE_SECTION_END \(label) frames=\(index)")
    }
}
#endif
