#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板位置钉住探针（仅 DEBUG）

/// 在同一次展开里逐页切过去，记录 popover 窗口的**屏幕坐标右上角**，验证「切页不再带着面板跑」
///
/// 触发方式：`NM_PANEL_PIN_PROBE=1 <app 可执行文件>`
///
/// 为什么要在**同一个进程的同一次展开**里测：跨进程重启时每个分页都是一次全新的展开，
/// 顶边本来就该重新锁（用户下次点开时面板贴在菜单栏下沿是正确行为）。
/// 「切页时面板位置恒定」这条契约只有同一进程连续切页才能验。
///
/// 输出口径（Cocoa 坐标，原点左下）：每个分页一行 frame + 右上角，最后一行给出右上角的取值集合。
/// 判据：右上角集合只有一个元素；高度随分页变化（分页内容确实不同）。
@MainActor
enum PanelPinProbe {

    static let environmentKey = "NM_PANEL_PIN_PROBE"

    /// 探针要巡览的分页（按分段条顺序）
    private static let tabs: [MenuPanelTab] = [.network, .credits, .token, .system]

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey]?.isEmpty == false
    }

    /// 跑一次巡览并把结果写到标准输出（探针自行退出进程）
    static func run(manager: MenuBarManager) {
        Task { @MainActor in
            // 与 NM_SHOW_PANEL 同一时序约束：晚于 1.2s 预热 + 它的 performClose（toggle 有 0.25s 防抖）
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            manager.openPanelForEvidence()
            // 等出场动画结束（PanelWindowPin 也是在动画结束后才锁顶边）
            try? await Task.sleep(nanoseconds: 900_000_000)

            var corners: [String] = []
            for tab in tabs {
                manager.selectTabForEvidence(tab)
                // 等高度重算 + 补钉落地
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let info = manager.evidenceWindow() else {
                    print("PROBE_FAIL tab=\(tab.stableID) 取不到面板窗口")
                    exit(1)
                }
                let frame = info.frame
                let corner = String(format: "%.1f,%.1f", frame.maxX, frame.maxY)
                corners.append(corner)
                print(String(format: "PROBE_TAB %@ x=%.1f y=%.1f w=%.1f h=%.1f corner=%@",
                             tab.stableID, frame.minX, frame.minY, frame.width, frame.height, corner))
            }
            let unique = Set(corners)
            print("PROBE_CORNERS " + unique.sorted().joined(separator: " | "))
            print(unique.count == 1 ? "PROBE_OK 右上角恒定" : "PROBE_FAIL 右上角有 \(unique.count) 个取值")
            exit(unique.count == 1 ? 0 : 1)
        }
    }
}
#endif
