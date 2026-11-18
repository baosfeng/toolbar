import Foundation
import NetworkMonitorUI

// MARK: - 截图全程不出现 Dock 图标（策略审计 + 源码守卫）
//
// 用户口径：「每次截图 dock 栏都会出现我们的软件」。根因是三处 setActivationPolicy(.regular)——
// 启动预热、抓屏前抢前台、覆盖层进入交互态。这类调用编译得过、功能测得通，
// 只有用户看得见 Dock，所以判据必须写成测试：审计运行期采样 + 扫描源码树。

// MARK: - 运行期审计（每个采样点都必须是 .accessory）

/// 判据是「每个采样点都是 .accessory」，不是「最后切回来了」——切回来 Dock 上已经闪过。
func runSnipActivationAuditTests() {
    print("\n🧪 Testing 截图激活策略审计（全程不出现 Dock 图标）...")

    let clean = [
        SnipPolicySample(phase: .idle, isAccessory: true),
        SnipPolicySample(phase: .captureBegin, isAccessory: true),
        SnipPolicySample(phase: .captureReady, isAccessory: true),
        SnipPolicySample(phase: .captureEnded, isAccessory: true),
    ]
    assertEqual(SnipActivationAudit.isClean(clean), true, "全程 accessory 的流程无越界")
    assertEqual(SnipActivationAudit.violations(in: clean), [], "越界列表为空")
    assertEqual(SnipActivationAudit.endsInMenuBar(clean), true, "收尾仍在菜单栏态")

    // 中途借出：哪怕最后切回来了也算越界（用户看到的那一下就是越界本身）
    let borrowedThenReturned = [
        SnipPolicySample(phase: .idle, isAccessory: true),
        SnipPolicySample(phase: .captureBegin, isAccessory: false),
        SnipPolicySample(phase: .captureReady, isAccessory: false),
        SnipPolicySample(phase: .captureEnded, isAccessory: true),
    ]
    assertEqual(SnipActivationAudit.isClean(borrowedThenReturned), false, "切回 .accessory 仍算越界")
    assertEqual(SnipActivationAudit.violations(in: borrowedThenReturned),
                [.captureBegin, .captureReady],
                "越界相位按出现顺序去重")
    assertEqual(SnipActivationAudit.endsInMenuBar(borrowedThenReturned), true, "收尾判据只看最后一个采样点")

    // 漏切回：取消 / 失败分支的典型形态
    let leaked = [
        SnipPolicySample(phase: .idle, isAccessory: true),
        SnipPolicySample(phase: .captureReady, isAccessory: false),
    ]
    assertEqual(SnipActivationAudit.endsInMenuBar(leaked), false, "结束时停在 .regular 即判失败")
    assertEqual(SnipActivationAudit.violations(in: leaked), [.captureReady], "漏切回给出具体相位")

    // 同一相位多次越界只报一次（采样是高频的，不能把同一处刷屏）
    let repeated = (0..<5).map { _ in SnipPolicySample(phase: .savePanel, isAccessory: false) }
    assertEqual(SnipActivationAudit.violations(in: repeated), [.savePanel], "同一相位去重")

    // 空采样不能算通过：探针没跑到就没有证据
    assertEqual(SnipActivationAudit.isClean([]), true, "空采样没有越界项")
    assertEqual(SnipActivationAudit.endsInMenuBar([]), false, "空采样不能证明回到菜单栏态")

    // 相位命名（失败信息要能直读）
    assertEqual(SnipPolicyPhase.allCases.count, 6, "六个相位都在")
    for phase in SnipPolicyPhase.allCases {
        assertEqual(phase.displayName.isEmpty, false, "相位都有可读名：\(phase.rawValue)")
    }

    let message = SnipActivationAudit.failureMessage([.captureReady, .savePanel])
    assertEqual(message.contains("覆盖层上屏"), true, "失败信息列出越界相位")
    assertEqual(message.contains("另存为面板"), true, "失败信息列出全部越界相位")
    assertEqual(message.contains("SnipActivationPolicy"), true, "失败信息给出改法")

    print("✅ 截图激活策略审计通过（切回也算越界，漏切回必报）")
}

// MARK: - 源码守卫（截图链路一处 .regular 都不许留）

/// 一处豁免：某个文件被允许把 App 切成 .regular
struct SnipPolicySourceExemption {
    /// 相对 Sources/NetworkMonitor/ 的路径（与扫描输出同口径）
    let path: String
    /// 为什么豁免（写给下一个要加调用点的人看）
    let reason: String
}

/// 一次命中：文件 + 行号
struct SnipPolicySourceHit: Equatable {
    let path: String
    let line: Int

    var readable: String { "\(path):\(line)" }
}

/// 策略守卫：判定逻辑 + 真实源码树扫描
enum SnipPolicySourceGuard {

    /// 被守卫的写法：把 App 变成「有 Dock 图标」的调用；.accessory / .prohibited 是收紧，不在此列
    static let guardedPattern = ".setActivationPolicy(.regular)"

    /// 白名单：当前没有任何文件可以切 .regular
    ///
    /// 截图链路（抓屏 / 覆盖层 / 导出 / 启动预热）只需要键盘投递，不需要 Dock 图标，
    /// 见 SnipForegroundPolicy；将来确有需要（例如正式文档式窗口）再逐条加进来并写理由。
    static let whitelist: [SnipPolicySourceExemption] = []

    /// 扫一批源码，找出白名单外的命中
    static func violations(sources: [String: String],
                           whitelist: [SnipPolicySourceExemption]) -> [SnipPolicySourceHit] {
        let allowed = Set(whitelist.map(\.path))
        var hits: [SnipPolicySourceHit] = []
        for (path, text) in sources where !allowed.contains(path) {
            for (index, code) in linesWithoutComments(text).enumerated() where code.contains(guardedPattern) {
                hits.append(SnipPolicySourceHit(path: path, line: index + 1))
            }
        }
        return hits.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
    }

    /// 去掉行注释（行号保持对齐：失败信息要指到真实那一行）
    static func linesWithoutComments(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            guard let range = line.range(of: "//") else { return line }
            return String(line[line.startIndex..<range.lowerBound])
        }
    }

    /// 源码根 = <repo>/NetworkMonitor/Sources/NetworkMonitor
    static func sourceRoot(swiftFilePath: String = #filePath) -> URL? {
        let fileURL = URL(fileURLWithPath: swiftFilePath)
        let sourcesDir = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            sourcesDir.appendingPathComponent("NetworkMonitor"),
            cwd.appendingPathComponent("Sources/NetworkMonitor"),
            cwd.appendingPathComponent("NetworkMonitor/Sources/NetworkMonitor"),
        ]
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    /// 递归读取源码树（相对路径 → 内容）
    static func loadSources(root: URL) -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [String: String] = [:]
        let prefix = root.path + "/"
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result[url.path.replacingOccurrences(of: prefix, with: "")] = text
        }
        return result
    }

    /// 失败信息
    static func failureMessage(_ hits: [SnipPolicySourceHit]) -> String {
        var lines = ["❌ 有 \(hits.count) 处把 App 切成 .regular（截图时 Dock 会出现图标）"]
        for hit in hits { lines.append("   • \(hit.readable)") }
        lines.append("")
        lines.append("改法：抢前台走 SnipForegroundPolicy.claimForeground()（只 activate，不切策略）；")
        lines.append("     覆盖层用 .nonactivatingPanel + canBecomeKey 收键盘，不需要 .regular。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 用例

func runSnipPolicySourceGuardTests() {
    print("\n🧪 Testing 激活策略守卫（截图链路不许切 .regular）...")

    let sample = ["import AppKit", "", "NSApp.setActivationPolicy(.regular)"].joined(separator: "\n")
    assertEqual(SnipPolicySourceGuard.violations(sources: ["Snip/Foo.swift": sample], whitelist: []),
                [SnipPolicySourceHit(path: "Snip/Foo.swift", line: 3)],
                "白名单外出现 .regular 即命中")

    // 注释里提到的同一写法不算（说明与真实调用必须区分）
    let commented = ["// 历史实现是 NSApp.setActivationPolicy(.regular)，已下线",
                     "NSApp.setActivationPolicy(.accessory)"].joined(separator: "\n")
    assertEqual(SnipPolicySourceGuard.violations(sources: ["Snip/Bar.swift": commented], whitelist: []),
                [],
                "注释里提到的写法与 .accessory 都不算命中")

    // 白名单放行
    assertEqual(SnipPolicySourceGuard.violations(
                    sources: ["Settings/SomeWindow.swift": sample],
                    whitelist: [SnipPolicySourceExemption(path: "Settings/SomeWindow.swift", reason: "测试用")]),
                [],
                "白名单内放行")

    // 真实源码树：截图链路必须一处都不剩
    guard let root = SnipPolicySourceGuard.sourceRoot() else {
        print("❌ 找不到源码根 Sources/NetworkMonitor（#filePath 反推失败）")
        exit(1)
    }
    let sources = SnipPolicySourceGuard.loadSources(root: root)
    assertEqual(sources.isEmpty, false, "源码树非空（否则守卫形同虚设）")
    let hits = SnipPolicySourceGuard.violations(sources: sources, whitelist: SnipPolicySourceGuard.whitelist)
    guard hits.isEmpty else {
        print(SnipPolicySourceGuard.failureMessage(hits))
        exit(1)
    }
    // 同一份源码里必须还能读到收尾归位调用：否则守卫可能扫错了目录
    assertEqual(sources.values.contains { $0.contains("SnipForegroundPolicy.restoreMenuBar") }, true,
                "源码树里能读到截图收尾的归位调用（确认扫的是本项目）")

    print("✅ 截图链路一处 .regular 都不剩（白名单 \(SnipPolicySourceGuard.whitelist.count) 项）")
}

// MARK: - 入口（两个套件一起跑：审计看运行期，守卫看源码）

func runSnipDockIconPolicyTests() {
    runSnipActivationAuditTests()
    runSnipPolicySourceGuardTests()
}
