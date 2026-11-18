#if DEBUG
import AppKit
import ApplicationServices
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 截图全程 Dock 图标自证（仅 DEBUG）

/// 走完一次真实截图流程（热键同款 beginSnip → 覆盖层上屏 → Esc 取消），
/// 同时记录两路证据：`NSApp.activationPolicy()` 与 Dock AX 树里的本应用条目数。
///
/// 触发方式：`NM_SNIP_DOCK_PROBE=1 dist/一览.app/Contents/MacOS/一览`
/// 产物：stdout 的逐相位采样 + 一行汇总结论（越界即 exit 1）
///
/// 为什么两路都要：策略是「原因」，Dock 条目是「用户看到的后果」。
/// 只看策略会漏掉「策略切回来了但图标已经闪现」这种情况在人工验收里的可见性；
/// 只看 Dock 则无法指出是哪一步借出了策略。
@MainActor
enum SnipDockProbe {

    static let envKey = "NM_SNIP_DOCK_PROBE"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    /// Dock 里本应用的条目数（AX 口径；基线在流程开始前取一次）
    static func dockItemCount() -> Int {
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return -1
        }
        let dock = AXUIElementCreateApplication(dockPID)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dock, kAXChildrenAttribute as CFString, &children) == .success,
              let lists = children as? [AXUIElement],
              let list = lists.first
        else { return -1 }
        var items: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &items) == .success,
              let dockItems = items as? [AXUIElement]
        else { return -1 }
        let name = AppIdentity.displayName
        return dockItems.filter { item in
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title) == .success else { return false }
            return (title as? String) == name
        }.count
    }

    /// 采样一次：策略 + Dock 条目数，并按相位记账
    @discardableResult
    static func sample(_ phase: SnipPolicyPhase) -> Int {
        SnipForegroundPolicy.record(phase)
        let count = dockItemCount()
        print("probe: 相位=\(phase.displayName) policy=\(NSApp.activationPolicy().rawValue) dockItems=\(count)")
        return count
    }

    /// 跑完整流程并给出结论
    static func run(controller: SnipController) {
        Task { @MainActor in
            // 等启动稳定：启动阶段的历史预热已下线，这里只是给窗口服务器一点时间
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            SnipForegroundPolicy.resetSamples()
            let baseline = sample(.idle)
            guard baseline >= 0 else {
                print("probe: 取不到 Dock 的 AX 树（需要给终端授「辅助功能」权限）")
                exit(2)
            }
            controller.beginSnip()
            // 覆盖层是异步上屏的（抓屏要几百毫秒）：轮询到它出现为止
            var waited = 0
            while controller.overlays.isEmpty, waited < 60 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                waited += 1
            }
            guard !controller.overlays.isEmpty else {
                print("probe: 覆盖层没有上屏，截图链路可能缺屏幕录制权限")
                exit(3)
            }
            sample(.captureReady)
            let overlay = controller.overlays.first
            print("probe: 覆盖层 isKeyWindow=\(overlay?.isKeyWindow ?? false) 系统层按键通道=\(controller.eventTap != nil ? "CGEventTap" : "本地监视器") appActive=\(NSApp.isActive)")
            // 停留一拍：Dock 图标若真会出现，这段延迟足以被采到
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                sample(.captureReady)
            }
            // 取消路径：默认自发 Esc（走覆盖层同一套 keyDown 处理）；
            // 环境变量给 wait 时改为等外部真实按键，用来验收「不切 .regular 也收得到键盘」
            let mode = ProcessInfo.processInfo.environment[envKey]
            if mode == "keys" {
                // 方向键自证：先摆一个选区，外部按方向键，再读选区是否真的移动
                guard let view = overlay?.overlayView else { exit(5) }
                view.debugApplySelection(CGRect(x: 400, y: 400, width: 300, height: 200))
                let before = view.state.selection ?? .zero
                print("probe: 按键前选区=\(rectText(before))，等待真实方向键 / 空格（4 秒）…")
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let after = view.state.selection ?? .zero
                print("probe: 按键后选区=\(rectText(after))")
                guard after != before else {
                    print("❌ 方向键没有改变选区（覆盖层没收到键盘）")
                    exit(6)
                }
                print("probe: 方向键已改变选区（覆盖层确实收到键盘）")
            }
            if mode == "wait" || mode == "keys" {
                print("probe: 等待真实键盘取消（5 秒内按 Esc）…")
                var waitedForKey = 0
                while !controller.overlays.isEmpty, waitedForKey < 50 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    waitedForKey += 1
                    sample(.captureReady)
                }
                guard controller.overlays.isEmpty else {
                    print("❌ 5 秒内没收到真实键盘取消事件（覆盖层未接管键盘）")
                    exit(4)
                }
                print("probe: 真实键盘已送达，覆盖层已收掉")
            } else {
                controller.overlays.first?.overlayView.handleKeyEvent(keyDownEvent(keyCode: 53))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            let after = sample(.captureEnded)
            // 另存为面板：⌘S 那条路也验一次（历史实现同样切过 .regular）
            savePanelCheck(controller: controller)
            let afterPanel = sample(.savePanel)
            report(baseline: baseline, after: max(after, afterPanel))
        }
    }

    /// 造一条 Esc 键按下事件（走覆盖层同一条 keyDown 处理路径）
    private static func keyDownEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown,
                         location: .zero,
                         modifierFlags: [],
                         timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: 0,
                         context: nil,
                         characters: "\u{1B}",
                         charactersIgnoringModifiers: "\u{1B}",
                         isARepeat: false,
                         keyCode: keyCode)!
    }


    /// 另存为面板自证：面板必须能成为 key window，且策略始终留在菜单栏态
    ///
    /// 面板是 `runModal` 起的模态循环，普通定时器不跑；这里把取消定时器挂到
    /// `.modalPanel` 模式上，等面板真的可见并成为 key 之后再采样、再取消。
    private static func savePanelCheck(controller: SnipController) {
        guard let image = makeProbeImage() else {
            print("probe: 造不出探针图，跳过另存为面板自证")
            return
        }
        var panelKey = false
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated {
                let visible = NSApp.modalWindow?.isVisible ?? false
                panelKey = NSApp.modalWindow?.isKeyWindow ?? false
                print("probe: 另存为面板 visible=\(visible) isKeyWindow=\(panelKey) policy=\(NSApp.activationPolicy().rawValue)")
                NSApp.modalWindow?.orderOut(nil)
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        controller.presentSavePanel(for: image)
        print("probe: 另存为面板收尾 policy=\(NSApp.activationPolicy().rawValue) 面板曾拿到键盘=\(panelKey)")
    }

    /// 1×1 白色图（只为了让保存面板有个可写的数据源，不落盘）
    private static func makeProbeImage() -> CGImage? {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(gray: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context?.makeImage()
    }

    /// 选区文本（探针输出用）
    private static func rectText(_ rect: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }
    /// 汇总：越界相位 + Dock 是否多出条目，任一不合即 exit 1
    private static func report(baseline: Int, after: Int) {
        let violations = SnipActivationAudit.violations(in: SnipForegroundPolicy.samples)
        let endsClean = SnipActivationAudit.endsInMenuBar(SnipForegroundPolicy.samples)
        print("probe: 采样 \(SnipForegroundPolicy.samples.count) 次，基线 dockItems=\(baseline)，结束时 dockItems=\(after)")
        guard violations.isEmpty, endsClean, after <= baseline else {
            if !violations.isEmpty { print(SnipActivationAudit.failureMessage(violations)) }
            if !endsClean { print("❌ 截图结束时激活策略不是 .accessory") }
            if after > baseline { print("❌ Dock 里多出了本应用图标：\(baseline) → \(after)") }
            exit(1)
        }
        print("✅ 截图全程未出现 Dock 图标（策略恒为 .accessory，Dock 条目 \(baseline) → \(after)）")
        exit(0)
    }
}
#endif
