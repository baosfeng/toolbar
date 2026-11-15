import AppKit
import ApplicationServices

// MARK: - 目标进程定位

/// 目标 app —— 只按 pid 直连，绝不启动新实例
///
/// 为什么不用 cua.getApp：那条路每次调用都会再拉起一个实例（实测一次搞出 9 个进程），
/// 菜单栏 app 多开后会互相抢状态项，取证数据全废。这里只用 NSWorkspace 的运行中列表匹配，
/// 命中不到就立刻报错，让调用方自己去启动。
struct AppTarget {
    let pid: pid_t
    let name: String
    let bundleID: String

    /// ax 根元素（每次读取都新建：AX 元素持有窗口快照，久放会指向已销毁的窗口）
    var axRoot: AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// 按名字 / bundle id / pid 解析运行中的 app
    ///
    /// 匹配优先级：纯数字当 pid → bundle id 精确 → 本地化名精确 → 可执行名精确 → 名字包含。
    /// 全部只查 runningApplications，不触发任何启动。
    static func resolve(_ token: String) throws -> AppTarget {
        let running = NSWorkspace.shared.runningApplications
        if let pid = pid_t(token) {
            guard let app = running.first(where: { $0.processIdentifier == pid }) else {
                throw CLIError("pid \(pid) 不在运行中（本 CLI 从不启动新实例）")
            }
            return make(app)
        }
        let candidates = running.filter { $0.bundleIdentifier != nil }
        if let app = candidates.first(where: { $0.bundleIdentifier == token }) {
            return make(app)
        }
        if let app = candidates.first(where: { $0.localizedName == token }) {
            return make(app)
        }
        if let app = candidates.first(where: { $0.executableURL?.lastPathComponent == token }) {
            return make(app)
        }
        if let app = candidates.first(where: { ($0.localizedName ?? "").contains(token) }) {
            return make(app)
        }
        let known = candidates.compactMap { $0.localizedName }.sorted()
        throw CLIError("找不到运行中的 app「\(token)」；当前可见：\(known.joined(separator: "、"))")
    }

    private static func make(_ app: NSRunningApplication) -> AppTarget {
        AppTarget(pid: app.processIdentifier,
                  name: app.localizedName ?? "?",
                  bundleID: app.bundleIdentifier ?? "-")
    }

    /// 同名多实例警告：菜单栏 app 多开时状态项会互相抢，取证数据不可信
    ///
    /// 本 CLI 不负责杀进程——只提醒调用方，让它自己决定复用哪个（用 pid 参数可以精确指定）。
    static func warnIfMultipleInstances(named name: String) {
        let sameName = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == name && $0.bundleIdentifier != nil
        }
        guard sameName.count > 1 else { return }
        let pids = sameName.map { String($0.processIdentifier) }.joined(separator: "、")
        Out.note("警告：\(name) 有 \(sameName.count) 个实例在运行（pid \(pids)）；"
                 + "当前用第一个，需要精确指定时把 app 参数换成 pid")
    }
}

// MARK: - 输出的 app 行

extension AppTarget {
    /// 「pid / bundleId / 名字 / 窗口数」一行；窗口数含 NSPanel（CGWindowList 口径）
    ///
    /// `windowCounts` 由调用方一次性统计后传入：`apps` 要列上百个进程，
    /// 每个都重新枚举一次全量窗口（本机 600+ 个）会让这条命令从毫秒级变成秒级。
    func describeForList(windowCounts: [pid_t: Int]) -> String {
        "\(pid)\t\(bundleID)\t\(name)\t\(windowCounts[pid] ?? 0)"
    }
}
