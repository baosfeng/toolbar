#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - L4 交互层自证（仅 DEBUG）

/// 自绘交互层的真实视图自证 —— 逐行追加的报告 + 五张真实绘制图
///
/// 触发：`NM_DRAWN_INTERACTION_PROBE=<输出目录>`
/// 产出：
/// - `drawn-interaction-probe.txt`：悬停目标 / 过渡值 / 减弱动效落终态 / 焦点环 / 无障碍 / 卡头按钮优先级
/// - `drawn-interaction-rows.png` / `-rows-nohover.png`：行列表（第 2 行悬停、第 4 行键盘焦点 / 无悬停对照）
/// - `drawn-interaction-card-focus.png` / `-card-nofocus.png`：系统卡（有 / 无键盘焦点环）
///
/// 为什么不用合成鼠标事件打真窗口：离屏窗口收不到事件，但 `mouseMoved` / `mouseDown` 是视图自己的
/// 入口方法，用真实 `NSEvent` 直接调用会走完「事件 → 命中 → 状态机 → 过渡 → 重绘」整条链路。
@MainActor
enum DrawnInteractionProbe {

    /// 探针开关
    static let envKey = "NM_DRAWN_INTERACTION_PROBE"

    /// 报告文件（逐行追加：中途异常也能留下已经走到的断言）
    private static var reportURL: URL?

    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment[envKey], !path.isEmpty else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("drawn-interaction-probe.txt")
        try? "".write(to: url, atomically: true, encoding: .utf8)
        reportURL = url
        record("# 自绘交互层自证（L4）")
        record("")
        rowListSection(directory: directory)
        record("")
        systemCardSection(directory: directory)
        exit(0)
    }

    // MARK: 行列表

    private static func rowListSection(directory: URL) {
        record("## 行列表（DrawnRowList）：悬停 / 过渡 / 焦点环 / 无障碍")
        let list = DrawnRowList()
        list.rowSpacing = 2
        list.rows = (0..<5).map { index in
            DrawnRowSpec(title: "第 \(index) 行 · 进程示例",
                         value: "\(40 + index).0%",
                         progress: Double(40 + index) / 100,
                         isActionable: index == 0)
        }
        var presses: [Int] = []
        list.onRowAction = { presses.append($0) }

        let size = NSSize(width: 300, height: list.intrinsicContentSize.height)
        let window = offscreenWindow(size: size)
        list.frame = NSRect(origin: .zero, size: size)
        window.contentView?.addSubview(list)
        window.contentView?.layoutSubtreeIfNeeded()

        // 1) 悬停进入第 2 行：mouseMoved → 命中 → 状态机 → 过渡
        move(list, toRow: 2, in: window)
        record("- 鼠标移入第 2 行：hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")（期望 2）")
        let entered = settleUntil(0.4) { list.hoverBlend.value >= 0.999 }
        record("- 过渡帧推进后 hoverBlend=\(fmt(list.hoverBlend.value))（期望 1.00，过渡落终态；"
               + "在 \(entered ? "0.4s 内" : "超时")到达）")

        // 2) 行间空隙不算命中：高亮淡出后停止绘制
        let gapY = list.rowRect(2).maxY + 1
        list.mouseMoved(with: event(.mouseMoved,
                                   at: list.convert(CGPoint(x: 40, y: gapY), to: nil),
                                   window: window))
        record("- 移到行间空隙：hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")（期望 2：淡出期间仍画）")
        let faded = settleUntil(0.4) { list.hoverBlend.value <= 0.001 && list.hoverIndex == nil }
        record("- 淡出后：hoverBlend=\(fmt(list.hoverBlend.value))（期望 0.00）、"
               + "hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")（期望 nil；"
               + "在 \(faded ? "0.4s 内" : "超时")到达）")

        // 3) 跨行移动
        move(list, toRow: 1, in: window)
        record("- 从第 2 行换到第 1 行：hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")（期望 1）")
        _ = settleUntil(0.4) { list.hoverBlend.value >= 0.999 }

        // 4) 减弱动效（省电档关闭动效）：直接落终态，不逐帧
        MotionKit.apply(profile: RenderTierLogic.powerSave)
        move(list, toRow: 3, in: window)
        record("- 省电档（动效关）移入第 3 行：立即 hoverBlend=\(fmt(list.hoverBlend.value))"
               + "（期望 1.00，无过渡帧）、hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")（期望 3）")
        list.mouseExited(with: event(.mouseMoved, at: .zero, window: window))
        record("- 省电档移出：立即 hoverBlend=\(fmt(list.hoverBlend.value))（期望 0.00）、"
               + "hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")（期望 nil）")
        MotionKit.resetDurations()

        // 5) 无障碍：逐行上报 + 可点击行可按下
        list.focusedIndex = 4
        let children = list.accessibilityChildren() ?? []
        record("- 无障碍子元素数=\(children.count)（期望 5 = 行数）")
        let elements = children.compactMap { $0 as? DrawnRowAccessibilityElement }
        record("- 第 0 行：role=\(elements.first?.accessibilityRole()?.rawValue ?? "nil")，"
               + "label=\(elements.first?.accessibilityLabel() ?? "nil")")
        record("- 第 4 行：role=\(elements.last?.accessibilityRole()?.rawValue ?? "nil")，"
               + "label=\(elements.last?.accessibilityLabel() ?? "nil")")
        let firstFrame = elements.first?.accessibilityFrame() ?? .zero
        record("- 第 0 行元素框=\(fmt(firstFrame.minX)),\(fmt(firstFrame.minY)) "
               + "\(fmt(firstFrame.width))×\(fmt(firstFrame.height))（宽 300 = 视图宽）")
        _ = elements.first?.accessibilityPerformPress()
        record("- 按下第 0 行（可点击行）：onRowAction 回调 \(presses.count) 次，下标=\(presses)（期望 [0]）")
        _ = elements.last?.accessibilityPerformPress()
        record("- 按下第 4 行（只读行）：onRowAction 累计 \(presses.count) 次（期望 1：只读行不可按下）")

        // 6) 出图：第 2 行悬停（过渡落终态）+ 第 4 行焦点环
        move(list, toRow: 2, in: window)
        _ = settleUntil(0.4) { list.hoverBlend.value >= 0.999 }
        record("- 出图状态：hoverIndex=\(list.hoverIndex.map(String.init) ?? "nil")、"
               + "hoverBlend=\(fmt(list.hoverBlend.value))、focusedIndex=\(list.focusedIndex.map(String.init) ?? "nil")")
        draw(list, size: size, to: directory.appendingPathComponent("drawn-interaction-rows.png"))
        list.mouseExited(with: event(.mouseMoved, at: .zero, window: window))
        _ = settleUntil(0.4) { list.hoverBlend.value <= 0.001 }
        draw(list, size: size, to: directory.appendingPathComponent("drawn-interaction-rows-nohover.png"))
    }

    // MARK: 系统卡

    private static func systemCardSection(directory: URL) {
        record("## 系统页整卡（SystemCardView）：焦点环 / 卡头按钮优先级 / 无障碍")
        let card = SystemCPUCardView(title: "CPU", trailing: "8 核 · 采样 1s")
        card.update(nil)
        var taps = 0
        var actionTaps = 0
        card.onTap = { taps += 1 }
        card.headAction = SystemCardView.HeadAction(title: "全部 ›",
                                                    font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                                                    color: SystemPalette.meta,
                                                    tip: "进入 CPU 详情",
                                                    activate: { actionTaps += 1 })
        let size = NSSize(width: 296, height: card.intrinsicContentSize.height)
        let window = offscreenWindow(size: size)
        card.frame = NSRect(origin: .zero, size: size)
        window.contentView?.addSubview(card)
        window.contentView?.layoutSubtreeIfNeeded()

        card.setCardKeyboardFocused(true)
        let children = card.accessibilityChildren() ?? []
        record("- 卡级子元素数=\(children.count)（期望 2：卡头按钮 + 内容读数）")
        let actionElement = children.first as? DrawnRowAccessibilityElement
        let contentElement = children.last as? DrawnRowAccessibilityElement
        record("- 卡头按钮：role=\(actionElement?.accessibilityRole()?.rawValue ?? "nil")，"
               + "label=\(actionElement?.accessibilityLabel() ?? "nil")")
        record("- 内容读数：role=\(contentElement?.accessibilityRole()?.rawValue ?? "nil")，"
               + "label=\(contentElement?.accessibilityLabel() ?? "nil")")
        let contentFrame = contentElement?.accessibilityFrame() ?? .zero
        record("- 内容读数元素框=\(fmt(contentFrame.minX)),\(fmt(contentFrame.minY)) "
               + "\(fmt(contentFrame.width))×\(fmt(contentFrame.height))")

        // 卡头按钮压在整卡上：同一个点必须先命中按钮（区域优先级）
        let actionRect = card.headActionRect
        card.mouseDown(with: event(.leftMouseDown,
                                  at: card.convert(CGPoint(x: actionRect.midX, y: actionRect.midY), to: nil),
                                  window: window))
        record("- 点卡头按钮中心：按钮回调 \(actionTaps) 次 / 整卡回调 \(taps) 次（期望 1 / 0）")
        card.mouseDown(with: event(.leftMouseDown,
                                  at: card.convert(CGPoint(x: 40, y: size.height - 8), to: nil),
                                  window: window))
        record("- 点卡内容区：整卡回调 \(taps) 次（期望 1）")
        _ = card.accessibilityPerformPress()
        record("- 读屏按下整卡：整卡回调 \(taps) 次（期望 2）")
        _ = actionElement?.accessibilityPerformPress()
        record("- 读屏按下卡头按钮：按钮回调 \(actionTaps) 次（期望 2）")

        draw(card, size: size, to: directory.appendingPathComponent("drawn-interaction-card-focus.png"))
        card.setCardKeyboardFocused(false)
        draw(card, size: size, to: directory.appendingPathComponent("drawn-interaction-card-nofocus.png"))
        record("- 出图：有焦点 / 无焦点各一张（差集即焦点环像素）")
    }

    // MARK: 工具

    private static func record(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
        guard let reportURL, let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: reportURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    /// 出图前把视图从临时窗口摘掉：离屏渲染会自己建窗口与约束
    private static func draw(_ view: NSView, size: NSSize, to url: URL) {
        view.removeFromSuperview()
        MenuPanelSnapshot.render(view: view, size: size, appearanceName: .aqua, to: url)
    }

    private static func offscreenWindow(size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSView(frame: NSRect(origin: .zero, size: size))
        return window
    }

    private static func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 0)!
    }

    /// 把鼠标移到某一行（走真实 mouseMoved 入口）
    private static func move(_ list: DrawnRowList, toRow index: Int, in window: NSWindow) {
        let rect = list.rowRect(index)
        list.mouseMoved(with: event(.mouseMoved,
                                   at: list.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil),
                                   window: window))
    }

    /// 跑 runloop 直到条件成立（上限 seconds）：返回是否在时限内成立
    ///
    /// 不用固定时长 sleep 的原因：离屏探针里第一次 `RunLoop.run(until:)` 会被启动期事件提前唤醒，
    /// 过渡帧还没跑完就返回，读数会假性停在起始值。按条件轮询才与真实节流无关。
    private static func settleUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
#endif
