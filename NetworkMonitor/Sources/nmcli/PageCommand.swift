import AppKit
import Foundation
import NetworkMonitorUI

// MARK: - 页面输出命令（nmcli page）

/// `nmcli page` —— 让运行中的 app 打开指定页面，并把当前页面截图输出
///
/// 与旧 `NM_*` 探针的区别（这决定了它为什么是新命令而不是保留探针）：
/// - 探针：带环境变量另起一个实例 → 离屏渲染 → `exit(0)`。取证必须先杀掉用户正在用的 app，
///   跑完还少一个进程；而且只能出「构造函数拼出来的假页面」，出不了用户眼前的真页面。
/// - 本命令：给已在运行的实例投一条分布式通知 → app 打开页面 → 回执窗口号 → `screencapture -l`。
///   全程不重启、不退出、不改偏好，跑完 app 继续正常用。
enum PageCommand {

    /// 发命令后等回执的上限（毫秒）
    static let defaultTimeoutMilliseconds = 5000

    static func run(_ args: Args) throws {
        let action = try args.positional(0, "action")
        switch action {
        case "list":
            listTargets()
        case "open":
            let raw = try args.positional(1, "target")
            let receipt = try send(try parseTarget(raw), timeoutMilliseconds: try timeout(args))
            Out.line("opened \(receipt.target) window=\(receipt.windowNumber)")
        case "shot":
            try shot(args)
        default:
            throw CLIError("未知 page 动作「\(action)」（可用：list / open / shot）")
        }
    }

    // MARK: 动作

    /// 列出可用目标 —— 让调用方不必去源码里翻字符串
    static func listTargets() {
        Out.line("# current 只输出当前已可见页面，不切换")
        Out.line("current")
        for id in CLIPageChannel.knownMenuTabIDs {
            Out.line("menu.\(id)")
        }
        Out.line("menu")
        for id in CLIPageChannel.knownSettingsSectionIDs {
            Out.line("settings.\(id)")
        }
        Out.line("settings")
        Out.line("clipboard")
    }

    /// 打开目标页面并截图落盘
    static func shot(_ args: Args) throws {
        guard let out = args.string("out") else { throw CLIError("缺少 --out <file>") }
        let raw = args.string("target") ?? "current"
        let target = try parseTarget(raw)
        let timeout = try timeout(args)

        let windowNumber: Int
        if target.needsOpening {
            windowNumber = try send(target, timeoutMilliseconds: timeout).windowNumber
        } else {
            windowNumber = try currentVisibleWindowNumber()
        }
        guard windowNumber > 0 else {
            throw CLIError("目标页面没有可用窗口（\(target.rawValue)）")
        }
        try waitUntilStable(windowNumber: windowNumber)
        let result = try Capture.shot(.window(windowNumber), to: out)
        Out.line(result.describe)
    }

    // MARK: 跨进程命令

    /// 一条回执
    struct Receipt {
        let target: String
        let windowNumber: Int
    }

    /// 投命令并等回执
    static func send(_ target: CLIPageTarget, timeoutMilliseconds: Int) throws -> Receipt {
        // 目标 app 必须先跑着：nmcli 从不替你启动实例（起两份实例会争同一个数据库与热键）
        _ = try AppTarget.resolve(defaultAppName)
        let request = UUID().uuidString
        let box = ReceiptBox()
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: Notification.Name(CLIPageChannel.receiptName),
            object: nil,
            queue: nil
        ) { notification in
            guard let info = notification.userInfo,
                  (info[CLIPageChannel.keyRequest] as? String) == request else { return }
            box.value = info
        }
        defer { center.removeObserver(observer) }

        center.postNotificationName(
            Notification.Name(CLIPageChannel.commandName),
            object: nil,
            userInfo: [
                CLIPageChannel.keyTarget: target.rawValue,
                CLIPageChannel.keyRequest: request,
            ],
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(Double(max(100, timeoutMilliseconds)) / 1000)
        while box.value == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard let info = box.value else {
            // 区分「app 没跑」与「app 版本老旧不认这条命令」：前者是用法问题，后者要升级包
            throw CLIError("等回执超时（\(timeoutMilliseconds)ms）："
                           + "确认「\(defaultAppName)」在运行，且这个包是带头 CLI 页面通道的构建")
        }
        let windowNumber = (info[CLIPageChannel.keyWindowNumber] as? Int)
            ?? Int(info[CLIPageChannel.keyWindowNumber] as? String ?? "")
            ?? 0
        return Receipt(target: info[CLIPageChannel.keyTarget] as? String ?? target.rawValue,
                       windowNumber: windowNumber)
    }

    /// 回执盒子 —— 分布式通知回调在别的线程，主线程靠它取结果
    private final class ReceiptBox: @unchecked Sendable {
        var value: [AnyHashable: Any]?
    }

    // MARK: 窗口与稳定判定

    /// 「当前页面」= 目标 app 眼下最上层的可见窗口（菜单面板 layer 25 / 设置窗口 layer 0）
    static func currentVisibleWindowNumber() throws -> Int {
        let target = try AppTarget.resolve(defaultAppName)
        // 取「真正看得见」的窗口里图层最高的那个：菜单面板 / 剪贴板浮层在 layer 25，
        // 设置窗口在 layer 0，所以面板开着时永远优先输出面板
        return WindowList.visibleWindows(of: target.pid)
            .max { $0.layer < $1.layer }?.id ?? 0
    }

    /// 等窗口尺寸连续两次采样一致 —— 面板有开合动画，动画中间态截出来是半张
    static func waitUntilStable(windowNumber: Int, attempts: Int = 40) throws {
        var previous: CGRect?
        for _ in 0..<attempts {
            let bounds = WindowList.all().first(where: { $0.id == windowNumber })?.bounds
            if let bounds, bounds.width >= 2, bounds == previous { return }
            previous = bounds
            usleep(50_000)
        }
        throw CLIError("窗口 \(windowNumber) 尺寸一直不稳定（面板动画没停？）")
    }

    // MARK: 解析辅助

    /// 目标 app 的默认名（与 AppIdentity.displayName 同源；`--app` 可覆盖）
    static var defaultAppName: String { "一览" }

    static func parseTarget(_ raw: String) throws -> CLIPageTarget {
        guard let target = CLIPageTarget.parse(raw) else {
            throw CLIError("未知页面「\(raw)」（nmcli page list 看可用目标）")
        }
        return target
    }

    static func timeout(_ args: Args) throws -> Int {
        try args.int("timeout") ?? defaultTimeoutMilliseconds
    }
}
