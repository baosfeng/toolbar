import CoreGraphics
import Foundation

// MARK: - 断言

/// 断言失败一律抛 `CLIError`：run 里某步断言失败即整条命令 exit 1
enum Assertions {

    /// 断言某窗口存在 / 不存在（layer 必填，可加 --title）
    static func window(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        let layer = try args.int("layer") ?? WindowInfo.panelLayer
        let title = args.string("title")
        let gone = args.flag("gone")
        let timeout = try args.int("timeout") ?? 0
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)

        func matched() -> WindowInfo? {
            WindowList.windows(of: target.pid).first { window in
                guard WindowList.isPresent(window, layer: layer) else { return false }
                if let title, !window.title.contains(title) { return false }
                return true
            }
        }

        repeat {
            let hit = matched()
            if gone ? hit == nil : hit != nil {
                return
            }
            if Date() >= deadline { break }
            usleep(50_000)
        } while true
        throw CLIError("断言失败：\(target.name) 应\(gone ? "不再有" : "有") layer=\(layer) 的窗口"
                       + (title.map { "（标题含「\($0)」）" } ?? "")
                       + "；实际窗口：\(WindowList.windows(of: target.pid).map(\.describe).joined(separator: " / "))")
    }

    /// 断言某元素存在（role / title / desc 任一组合）
    static func element(_ args: Args) throws {
        let target = try AppTarget.resolve(try args.positional(0, "app"))
        let role = args.string("role")
        let title = args.string("title")
        let desc = args.string("desc")
        let hits = AXRoots.collect(target, maxDepth: 16) { node in
            if let role, node.role != role { return false }
            if let title, node.title != title && node.value != title { return false }
            if let desc, !node.desc.localizedStandardContains(desc) { return false }
            return role != nil || title != nil || desc != nil
        }
        guard !hits.isEmpty else {
            throw CLIError("断言失败：没找到 role=\(role ?? "*") title=\(title ?? "*") desc=\(desc ?? "*") 的元素")
        }
    }

    /// 断言两张图差异不超过阈值
    static func pixels(_ args: Args) throws {
        guard args.positionals.count >= 3, args.positionals[1] == "vs" else {
            throw CLIError("用法：assert pixels <a.png> vs <b.png> [--max-diff 0.01]")
        }
        let maxDiff = try args.double("max-diff") ?? 0.01
        let ratio = try PixelDiff.ratio(args.positionals[0], args.positionals[2])
        guard ratio <= maxDiff else {
            throw CLIError(String(format: "断言失败：像素差异 %.4f > %.4f", ratio, maxDiff))
        }
        Out.line(String(format: "像素差异 %.4f ≤ %.4f", ratio, maxDiff))
    }
}
