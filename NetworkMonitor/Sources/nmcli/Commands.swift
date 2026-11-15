import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 单步命令实现

/// 每个子命令一个静态方法：参数解析留在 `main` 分发表，这里只做动作
enum Commands {

    // MARK: 列表类

    static func apps(_ args: Args) throws {
        Out.line("pid\tbundleId\tname\twindows")
        // 窗口数一次统计完再查：逐进程重扫全量窗口列表会让本命令退化成秒级
        var counts: [pid_t: Int] = [:]
        for window in WindowList.all() {
            counts[window.pid, default: 0] += 1
        }
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier != nil {
            let target = AppTarget(pid: app.processIdentifier,
                                   name: app.localizedName ?? "?",
                                   bundleID: app.bundleIdentifier ?? "-")
            Out.line(target.describeForList(windowCounts: counts))
        }
    }

    static func windows(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        let all = WindowList.windows(of: target.pid)
        let layerFilter = try args.int("layer")
        Out.line("# \(target.name) pid=\(target.pid) 窗口 \(all.count) 个（含离屏；NSPanel 只在 CGWindowList 里）")
        Out.line("id\tlayer\talpha\tonscreen\tbounds\ttitle")
        for window in all {
            if let layerFilter, window.layer != layerFilter { continue }
            Out.line(window.describe)
        }
    }

    static func ax(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        let depth = try args.int("depth") ?? 8
        let maxNodes = try args.int("max-nodes") ?? 800
        var count = 0
        AXRoots.walkAll(target, maxDepth: depth, maxNodes: maxNodes) { node in
            count += 1
            Out.line(node.describe)
        }
        Out.note("（\(count) 个节点，depth≤\(depth)）")
    }

    static func menubar(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        Out.line("# \(target.name) 菜单栏状态项（bounds 为现读 kAXPositionAttribute）")
        for item in MenuBarReader.statusItems(of: target) {
            Out.line("\(item.role)\t\(item.frameDescription)\tactions=[\(item.actions.joined(separator: ","))]\ttitle=\(item.title)")
        }
    }

    // MARK: 命中与查找

    static func at(_ args: Args) throws {
        let point = try parsePoint(args)
        guard let node = AXReader.element(at: point) else {
            throw CLIError("(\(Format.point(point))) 处没有元素（无障碍权限？）")
        }
        Out.line("\(Format.point(point))\t\(node.role)\t\(node.frameDescription)"
                 + "\ttitle=\(node.title)\tdesc=\(node.desc)\tvalue=\(node.value)")
    }

    static func find(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        for node in try search(args, target: target) {
            Out.line("\(node.role)\t\(node.frameDescription)\t\(node.center.map(Format.point) ?? "-")"
                     + "\ttitle=\(node.title)\tdesc=\(node.desc)")
        }
    }

    // MARK: 点击

    static func click(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        let matches = try search(args, target: target)
        guard let node = matches.first else {
            throw CLIError("没有匹配到元素（用 nmcli find 先看看有什么）")
        }
        if Actions.press(node) {
            Out.line("AXPress ok\t\(node.role)\t\(node.frameDescription)\t\(node.title)\(node.desc)")
            if isStatusItem(node, target: target) {
                PanelGeometry.settleAfterStatusItemPress(target)
                let state = PanelGeometry.panel(of: target).map { "面板已\($0.onscreen ? "开" : "关") \(Format.rect($0.bounds))" } ?? "面板已关"
                Out.line(state)
            }
            return
        }
        guard let center = node.center else {
            throw CLIError("元素没有坐标，且不支持 AXPress：\(node.role) \(node.title)\(node.desc)")
        }
        Actions.click(at: center)
        Out.line("坐标回退\t\(Format.point(center))\t\(node.role)\t\(node.frameDescription)")
    }

    static func clickAt(_ args: Args) throws {
        let point = try parsePoint(args)
        Actions.click(at: point)
        Out.line("clicked \(Format.point(point))")
    }

    static func hover(_ args: Args) throws {
        let point = try parsePoint(args)
        let hold = try args.int("hold") ?? 450
        Actions.hover(at: point, holdMilliseconds: hold)
        Out.line("hovered \(Format.point(point)) hold=\(hold)ms")
    }

    // MARK: 键盘

    static func type(_ args: Args) throws {
        let text = try args.positional(0, "text")
        Actions.type(text)
        Out.line("typed \(text.count) chars")
    }

    static func key(_ args: Args) throws {
        let combo = try args.positional(0, "combo")
        // 键盘事件只送给前台进程，所以要按到某个 app 上时必须先把它拉到前台
        var activated = ""
        if let app = args.string("app") {
            let target = try AppTarget.resolve(app)
            guard let running = NSRunningApplication(processIdentifier: target.pid) else {
                throw CLIError("激活失败：pid \(target.pid) 已退出")
            }
            _ = running.activate(options: [])
            usleep(300_000)
            activated = "（已激活 \(target.name)）"
        }
        try Actions.key(combo)
        Out.line("key \(combo)\(activated)")
    }

    // MARK: 截图与等待

    static func shot(_ args: Args) throws {
        guard let out = args.string("out") else { throw CLIError("缺少 --out <file>") }
        let source = try shotSource(args)
        let result = try Capture.shot(source, to: out)
        Out.line(result.describe)
    }

    static func shotSource(_ args: Args) throws -> Capture.Source {
        if let windowID = try args.int("window") { return .window(windowID) }
        if let rect = parseRect(args.string("rect")) { return .rect(rect) }
        if let app = args.string("app") {
            let target = try AppTarget.resolve(app)
            let layer = try args.int("layer") ?? WindowInfo.panelLayer
            guard let window = WindowList.panel(of: target.pid, layer: layer) else {
                throw CLIError("\(target.name) 没有可见的 layer=\(layer) 窗口")
            }
            return .window(window.id)
        }
        return .screen
    }

    static func wait(_ args: Args) throws {
        let milliseconds: Int
        if let explicit = try args.int("ms") {
            milliseconds = explicit
        } else {
            milliseconds = Int(try args.positional(0, "ms")) ?? 0
        }
        usleep(UInt32(max(0, milliseconds)) * 1000)
        Out.line("waited \(milliseconds)ms")
    }

    static func waitWindow(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        let layer = try args.int("layer") ?? WindowInfo.panelLayer
        let timeout = try args.int("timeout") ?? 2000
        let gone = args.flag("gone")
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
        repeat {
            let present = !WindowList.presentWindows(of: target.pid, layer: layer).isEmpty
            if present != gone {
                let window = WindowList.panel(of: target.pid, layer: layer)
                Out.line("layer=\(layer) \(gone ? "已消失" : "已出现")\t\(window?.describe ?? "-")")
                return
            }
            usleep(40_000)
        } while Date() < deadline
        throw CLIError("等 layer=\(layer) 的窗口 \(gone ? "消失" : "出现")超时（\(timeout)ms）")
    }

    /// 该元素是不是目标 app 的菜单栏状态项（按它相当于 toggle 面板）
    static func isStatusItem(_ node: AXNode, target: AppTarget) -> Bool {
        guard node.role == "AXMenuBarItem" else { return false }
        return MenuBarReader.statusItems(of: target).contains { CFEqual($0.element, node.element) }
    }

    // MARK: 解析辅助

    static func search(_ args: Args, target: AppTarget) throws -> [AXNode] {
        let role = args.string("role")
        let title = args.string("title")
        let desc = args.string("desc")
        let value = args.string("value")
        let depth = try args.int("depth") ?? 16
        var hits = AXRoots.collect(target, maxDepth: depth) { node in
            if let role, node.role != role { return false }
            if let title, node.title != title && node.value != title { return false }
            if let desc, !node.desc.localizedStandardContains(desc) { return false }
            if let value, node.value != value { return false }
            return role != nil || title != nil || desc != nil || value != nil
        }
        if let index = try args.int("index") {
            guard index >= 0, index < hits.count else {
                throw CLIError("--index \(index) 越界（共 \(hits.count) 个）")
            }
            hits = [hits[index]]
        }
        return hits
    }

    static func parsePoint(_ args: Args) throws -> CGPoint {
        let x = try args.positional(0, "x")
        let y = try args.positional(1, "y")
        guard let px = Double(x), let py = Double(y) else {
            throw CLIError("坐标需要数字，收到「\(x)」「\(y)」")
        }
        return CGPoint(x: px, y: py)
    }

    static func parseRect(_ text: String?) -> CGRect? {
        guard let text else { return nil }
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}
