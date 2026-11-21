#if DEBUG
import AppKit
import Darwin
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard
import NetworkMonitorUI

// MARK: - 剪贴板面板性能取证（仅 DEBUG）

/// 剪贴板卡片区的两项性能取证 —— 改前 / 改后用同一条命令对账
///
/// 两个开关各自跑完即退出进程：
/// - `NM_CLIPBOARD_FOOTPRINT=<文件>`：视图池装满 32 张卡片时的 footprint、视图台账与卡片区尺寸；
/// - `NM_CLIPBOARD_CAPTURE_TIMING=<文件>`：往独立粘贴板写一张 5K 图后跑一次采集，
///   量「主线程占用」与「从发起到落库回调」两段耗时。
///
/// 与 `NM_DRAWN_COUNT_TAB=clipboard`（视图台账）分开的原因：footprint 必须在渲染完成后
/// 仍在同一进程内读 `task_vm_info`，而台账探针抓完帧就 exit。
///
/// 独立粘贴板：采集计时探针读的是自建 `NSPasteboard` 实例，不碰用户剪贴板
/// （`PasteboardWatcher` 的 pasteboard 本就是构造器注入的）。
@MainActor
enum ClipboardPerfProbe {

    /// footprint 探针开关
    static let footprintEnvKey = "NM_CLIPBOARD_FOOTPRINT"
    /// 采集耗时探针开关
    static let captureTimingEnvKey = "NM_CLIPBOARD_CAPTURE_TIMING"

    /// 视图池装满时的卡片数（`ClipboardCardWindowPolicy.windowSize`）
    static let cardCount = ClipboardCardWindowPolicy.windowSize

    /// 入口：两个开关都没设置时立即返回 false
    static func runIfRequested() -> Bool {
        if let path = environment(footprintEnvKey) {
            runFootprint(path: path)
            return true
        }
        if let path = environment(captureTimingEnvKey) {
            runCaptureTiming(path: path)
            return true
        }
        return false
    }

    // MARK: - 夹具

    /// 32 条混合条目（文本 / 图片 / 文件 / RTF），与真实面板同一份数据结构
    ///
    /// 图片条目不带 imagePath：取证只量「卡片本身」的视图与 footprint，
    /// 不把缩略图缓存（另一份有界预算）混进本次对比口径。
    static func fixtureItems(count: Int = cardCount) -> [ClipboardItem] {
        let bodies = [
            "curl -I https://api.example.com/v1/status",
            "把这段命令贴进终端后回车",
            "{\"kind\": \"text\", \"contentHash\": \"abc123\"}",
            "https://github.com/swiftlang/swift-package-manager/issues",
            "SELECT id, content_hash FROM clipboard_items ORDER BY created_at DESC LIMIT 20;",
            "这是一段普通的中文正文，用来验证正文断行与最多 7 行的截断口径。",
            "git rebase --interactive origin/main",
            "https://www.apple.com/macos/sonoma/",
        ]
        let now = Date()
        return (0..<count).map { index in
            if index % 6 == 2 {
                return ClipboardItem(kind: .image,
                                     preview: "图片 5120×2880",
                                     imagePath: nil,
                                     imageWidth: 5120, imageHeight: 2880,
                                     contentHash: String(format: "probe-image-%02d", index),
                                     sourceBundleID: "com.apple.Safari",
                                     sourceAppName: "Safari",
                                     isPinned: index == 2,
                                     createdAt: now.addingTimeInterval(-Double(index) * 60),
                                     stackPosition: index < 3 ? index + 1 : nil)
            }
            if index % 7 == 3 {
                let path = "/Users/probe/Documents/设计稿-v\(index).png"
                return ClipboardItem(kind: .file,
                                     text: path,
                                     preview: "设计稿-v\(index).png",
                                     contentHash: String(format: "probe-file-%02d", index),
                                     sourceBundleID: "com.apple.finder",
                                     sourceAppName: "访达",
                                     createdAt: now.addingTimeInterval(-Double(index) * 60))
            }
            if index % 9 == 5 {
                return ClipboardItem(kind: .rtf,
                                     text: "富文本示例 \(index)",
                                     preview: "富文本示例 \(index)",
                                     contentHash: String(format: "probe-rtf-%02d", index),
                                     sourceBundleID: "com.apple.TextEdit",
                                     sourceAppName: "文本编辑",
                                     createdAt: now.addingTimeInterval(-Double(index) * 60))
            }
            let body = bodies[index % bodies.count]
            return ClipboardItem(kind: .text,
                                 text: body,
                                 preview: body,
                                 contentHash: String(format: "probe-text-%02d", index),
                                 sourceBundleID: index % 2 == 0 ? "com.apple.Terminal" : "com.apple.Notes",
                                 sourceAppName: index % 2 == 0 ? "终端" : "备忘录",
                                 copyCount: index % 3 + 1,
                                 isPinned: index == 4,
                                 createdAt: now.addingTimeInterval(-Double(index) * 60))
        }
    }

    // MARK: - footprint

    private static func runFootprint(path: String) {
        let items = fixtureItems()
        let size = NSSize(width: 640, height: 260)
        let canvas = SnapshotClipboardPanel(size: size, items: items).makeView()
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipboard-footprint-scratch.png")
        let baseline = footprintBytes()
        var views = "（未取到）"
        MenuPanelSnapshot.render(view: canvas, size: size, appearanceName: .aqua, to: scratch) { root in
            views = viewLedger(root)
        }
        let after = footprintBytes()
        let report = """
        # 剪贴板卡片区性能台账（32 张卡片视图池装满 · 640×260 画布）

        footprint_before_bytes = \(baseline)
        footprint_after_bytes = \(after)
        footprint_delta_mb = \(String(format: "%.1f", Double(after - baseline) / 1024 / 1024))
        footprint_after_mb = \(String(format: "%.1f", Double(after) / 1024 / 1024))
        ps_rss_after_kb = \(psRSS())
        card_count = \(items.count)

        \(views)
        """
        write(report, to: path)
        exit(0)
    }

    /// 画布视图台账：卡片区（卡片流子树里每张卡及其子视图）+ 面板总计
    ///
    /// internal：`NM_DRAWN_COUNT_TAB=clipboard` 的台账探针（DrawnUIProbe+ViewAudit）复用同一份计数。
    static func viewLedger(_ root: NSView) -> String {
        guard let panel = root.subviews.compactMap({ $0 as? ClipboardPanelView }).first else {
            return "panel_view = 未取到"
        }
        let flow = panel.cardFlow
        let cards = flow.cardViews
        var lines = ["# 视图台账", "",
                     "| 分组 | 内部视图数 | 含容器 |",
                     "|------|-----------|--------|"]
        var perCard: [Int] = []
        for card in cards {
            let interior = subtreeCount(card) - 1
            perCard.append(interior)
        }
        let cardTotal = perCard.reduce(0, +)
        if let first = perCard.first, perCard.allSatisfy({ $0 == first }) {
            lines.append("| 单张卡片（×\(perCard.count)） | \(first) | \(first + 1) |")
        } else {
            lines.append("| 单张卡片 | \(perCard.min() ?? 0)…\(perCard.max() ?? 0)（共 \(perCard.count) 张） | — |")
        }
        lines.append("| **卡片区内部视图合计** | **\(cardTotal)** | \(cardTotal + perCard.count) |")
        lines.append("| **卡片流（含滚动视图 / 容器 / 空态）** | \(subtreeCount(flow) - 1) | \(subtreeCount(flow)) |")
        lines.append("| **面板总计（含工具条 / 页脚 / 浮层）** | \(subtreeCount(panel) - 1) | \(subtreeCount(panel)) |")
        lines.append("")
        lines.append("card_visible_count = \(flow.visibleCount())")
        lines.append("card_pool_count = \(cards.count)")
        // TREE=1：逐层列出每张卡的子视图类型与 frame（改造前后按同一坐标系核对）
        if ProcessInfo.processInfo.environment["NM_DRAWN_COUNT_TREE"]?.isEmpty == false,
           let first = cards.first {
            lines.append("")
            lines.append("## 首张卡片视图树")
            lines.append("```")
            lines.append(contentsOf: cardTree(of: first))
            lines.append("```")
        }
        return lines.joined(separator: "\n")
    }

    /// 首张卡片的逐层视图树
    private static func cardTree(of card: NSView) -> [String] {
        var out: [String] = []
        func walk(_ view: NSView, depth: Int) {
            let frame = view.frame
            var line = String(repeating: "  ", count: depth) + "\(type(of: view))"
            line += " frame=(\(String(format: "%.1f", frame.minX)),\(String(format: "%.1f", frame.minY)),"
            line += "\(String(format: "%.1f", frame.width)),\(String(format: "%.1f", frame.height)))"
            if view.isHidden { line += " hidden" }
            out.append(line)
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        walk(card, depth: 0)
        return out
    }

    /// 子树视图总数（含自身）
    private static func subtreeCount(_ view: NSView) -> Int {
        1 + view.subviews.reduce(0) { $0 + subtreeCount($1) }
    }

    // MARK: - 采集耗时

    /// 往独立粘贴板写一张 5K PNG，量「主线程占用」与「回调总耗时」
    ///
    /// 判据：改后 `captureNow` 的主线程占用应与图片大小无关（只做 pasteboard 读取 + 提交），
    /// 图片哈希 / 落盘 / 缩略图 / PNG 编码全部在后台完成。
    private static func runCaptureTiming(path: String) {
        guard let data = make5KPNGData() else {
            write("fixture_png = 生成失败\n", to: path)
            exit(1)
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.bsfeng.macmonitor.clipboard.perfprobe"))
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: .png)
        pasteboard.writeObjects([pasteboardItem])

        let watcher = PasteboardWatcher(preferences: ClipboardPreferences(), logger: AppContext.shared.logger, pasteboard: pasteboard)
        var draft: ClipboardDraft?
        var callbackSeconds: Double = 0
        let start = CFAbsoluteTimeGetCurrent()
        watcher.onCapture = { captured in
            draft = captured
            callbackSeconds = CFAbsoluteTimeGetCurrent() - start
        }
        watcher.captureNow()
        let mainThreadMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let deadline = Date().addingTimeInterval(20)
        while draft == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let captured = draft
        let report = """
        # 5K 图粘贴的主线程占用

        fixture_png_bytes = \(data.count)
        image_pixels = 5120×2880
        main_thread_ms = \(String(format: "%.2f", mainThreadMilliseconds))
        capture_callback_ms = \(String(format: "%.2f", callbackSeconds * 1000))
        captured = \(captured != nil ? "是" : "否（超时 20s）")
        kind = \(captured.map { "\($0.kind.rawValue)" } ?? "—")
        preview = \(captured?.preview ?? "—")
        image_path = \(captured?.imagePath.map { LogRedaction.path($0) } ?? "—")
        content_hash = \(captured?.contentHash.prefix(12) ?? "—")
        """
        write(report, to: path)
        exit(0)
    }

    /// 造一张 5120×2880 的真实 PNG（渐变 + 文字），作为「粘贴一张 5K 图」的字节
    private static func make5KPNGData() -> Data? {
        let size = NSSize(width: 5120, height: 2880)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 240, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        ("5K 取证图" as NSString).draw(at: NSPoint(x: 400, y: 1200), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - 进程指标

    /// 进程物理 footprint（与「活动监视器」的内存口径一致；heap 之外含共享页的私有部分）
    static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint)
    }

    /// `ps -o rss=` 采样（与外部命令同口径，便于复核）
    private static func psRSS() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", "\(getpid())"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - 工具

    private static func environment(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func write(_ text: String, to path: String) {
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        } catch {
            AppContext.shared.logger.error("剪贴板性能探针写入失败：\(error.localizedDescription)")
        }
        FileHandle.standardError.write(Data(text.utf8))
    }
}
#endif
