import Foundation

// MARK: - 权限判据守卫（源码扫描）

// 为什么用「扫源码」而不是断言函数返回值：
// 这一类越界无法在运行期发现 —— 功能路径多调一次 AXIsProcessTrusted() 依然能编译、能跑对，
// 只是从此外面多了一份与 SystemPermissionCenter 可能分叉的判据（用户看到的权限状态与
// 功能实际行为不一致，正是「权限设置很多地方不统一」的根因）。
// 所以把「谁允许直呼系统权限 API」写成白名单，落在测试里失败即拦。

/// 一处豁免：某个文件被允许直接调用系统权限 API
struct PermissionSourceExemption {
    /// 相对 Sources/ 的路径，形如 <target>/文件.swift（与扫描输出同口径）
    let path: String
    /// 为什么豁免 —— 写给下一个要加调用点的人看，不写「历史原因」
    let reason: String
}

/// 一次命中：文件 + 行号 + 命中的符号
struct PermissionSourceHit: Equatable {
    let path: String
    let line: Int
    let symbol: String

    /// 可读单行（失败信息直接用）
    var readable: String { "\(path):\(line)  \(symbol)" }
}

/// 扫描结论
enum PermissionSourceGuardReport: Equatable {
    /// 全部命中都在白名单内（带每个文件的命中次数，便于人工复核白名单没被架空）
    case compliant(usageByPath: [String: Int])
    /// 有落在白名单外的命中
    case violations([PermissionSourceHit])
}

/// 权限判据守卫：判定逻辑（纯函数）+ 真实源码树扫描
enum PermissionSourceGuard {

    // MARK: 被守卫的 API

    /// 直接读系统权限状态的 API —— 按「包含即命中」处理
    ///
    /// AXIsProcessTrusted 同时覆盖 AXIsProcessTrustedWithOptions（同一家族，
    /// 后者只是多了 prompt 选项）；两条 CG 各自独立。
    static let guardedSymbols = [
        "AXIsProcessTrusted",
        "CGPreflightScreenCaptureAccess",
        "CGRequestScreenCaptureAccess",
    ]

    /// 白名单：当前只允许这四个文件直呼上面那些 API
    ///
    /// 新增调用点前先回答一个问题：能不能改成转发 SystemPermissionCenter？
    /// 能就必须转发（PasteStackController.probeAccessibility 就是范本）。
    static let whitelist: [PermissionSourceExemption] = [
        PermissionSourceExemption(
            path: "NetworkMonitor/Permissions/SystemPermissionCenter.swift",
            reason: "唯一读取点：五类权限的静默读取与显式请求都在这里，别处一律读它发布的快照"),
        PermissionSourceExemption(
            path: "NetworkMonitorFeatureClipboard/ClipboardPaster.swift",
            reason: "运行期即时判据：合成 ⌘V 之前必须知道此刻能不能投递事件，"
                  + "不能等一次快照刷新——否则会谎报「已粘贴」而事件被系统丢弃"),
        PermissionSourceExemption(
            path: "NetworkMonitor/Snip/ScreenCaptureService.swift",
            reason: "抓屏能力探测：preflight / request 是实际抓屏路径自身的前置条件，"
                  + "结果经 isAuthorized() 交给中心读取，不另存一份状态"),
        PermissionSourceExemption(
            path: "NetworkMonitorFeatureClipboard/PasteStackController.swift",
            reason: "转发：probeAccessibility() 是该 API 的唯一实现，"
                  + "SystemPermissionCenter 只转发它，两处各写一份选项字典必然分叉"),
    ]

    // MARK: 纯判定

    /// 扫一批源码，判定是否有越界调用
    ///
    /// - Parameters:
    ///   - sources: 相对路径 → 文件内容
    ///   - whitelist: 允许直呼 API 的文件（相对路径）
    static func report(sources: [String: String],
                       whitelist: [PermissionSourceExemption]) -> PermissionSourceGuardReport {
        let allowed = Set(whitelist.map(\.path))
        var violations: [PermissionSourceHit] = []
        var usageByPath: [String: Int] = [:]
        for (path, text) in sources {
            let hits = hits(in: text, path: path)
            guard !hits.isEmpty else { continue }
            usageByPath[path] = hits.count
            if !allowed.contains(path) { violations.append(contentsOf: hits) }
        }
        // 违规按「文件 + 行号」排序：失败信息要能一眼按源码顺序读
        guard violations.isEmpty else {
            return .violations(violations.sorted { ($0.path, $0.line) < ($1.path, $1.line) })
        }
        return .compliant(usageByPath: usageByPath)
    }

    /// 一个文件里的全部命中（行号已对齐原文）
    static func hits(in text: String, path: String) -> [PermissionSourceHit] {
        var result: [PermissionSourceHit] = []
        for (index, code) in codeOnlyLines(text).enumerated() {
            for symbol in guardedSymbols where code.contains(symbol) {
                result.append(PermissionSourceHit(path: path, line: index + 1, symbol: symbol))
            }
        }
        return result
    }

    // MARK: 去注释 / 去字符串（行号必须保持对齐）

    /// 去掉注释与字符串字面量内容，返回与原文逐行对齐的「纯代码」文本
    ///
    /// 两个理由：
    /// 1. 注释里说明 API 名字（如权限中心那句「CGRequestScreenCaptureAccess 弹一次提示」）
    ///    不是调用，直接按行匹配会把它算成越界；
    /// 2. 日志与提示文案里出现同一个词同理。
    /// 行号必须对齐：失败信息要指到真实那一行，删掉整行注释会让行号飘走。
    static func codeOnlyLines(_ text: String) -> [String] {
        var state: ScannerState = .code
        var lines: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            switch state {
            case .code:
                if ch == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    state = .lineComment
                    i += 2
                    continue
                }
                if ch == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    state = .blockComment
                    i += 2
                    continue
                }
                if ch == "\"" {
                    // 字符串内容整体抹掉（留一个空格占位，不影响行内其余代码）
                    state = .string
                    current.append(" ")
                    i += 1
                    continue
                }
                if ch == "\n" {
                    lines.append(current)
                    current = ""
                    i += 1
                    continue
                }
                current.append(ch)
                i += 1
            case .lineComment:
                if ch == "\n" {
                    lines.append(current)
                    current = ""
                    state = .code
                }
                i += 1
            case .blockComment:
                if ch == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                    state = .code
                    i += 2
                    continue
                }
                if ch == "\n" {
                    lines.append(current)
                    current = ""
                }
                i += 1
            case .string:
                // 转义符连跳两格：\" 不应结束字符串
                if ch == "\\" {
                    i += 2
                    continue
                }
                if ch == "\"" {
                    state = .code
                    i += 1
                    continue
                }
                if ch == "\n" {
                    lines.append(current)
                    current = ""
                }
                i += 1
            }
        }
        lines.append(current)
        return lines
    }

    /// 扫描器状态
    private enum ScannerState {
        case code
        case lineComment
        case blockComment
        case string
    }

    // MARK: 真实源码树

    /// 源码根 = <repo>/NetworkMonitor/Sources（扫全部 target，路径带 target 前缀）
    ///
    /// 扫全部 target：调用点随服务层拆分落到功能 target（ClipboardPaster 等已在
    /// NetworkMonitorFeatureClipboard），只扫 App 会让白名单项「0 次使用」而悄悄失效。
    /// 用 #filePath 逐级回退，不依赖运行期工作目录。
    static func sourceRoot(swiftFilePath: String = #filePath) -> URL? {
        let fileURL = URL(fileURLWithPath: swiftFilePath)
        // 本文件位于 Sources/TestRunner/，上跳两级即 Sources/
        let sourcesDir = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            sourcesDir,
            cwd.appendingPathComponent("Sources"),
            cwd.appendingPathComponent("NetworkMonitor/Sources"),
        ]
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    /// 递归读取源码树（相对路径 → 内容）
    static func loadSources(root: URL) -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                             includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [String: String] = [:]
        let prefix = root.path + "/"
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result[url.path.replacingOccurrences(of: prefix, with: "")] = text
        }
        return result
    }

    /// 失败信息：文件 + 行号 + 命中符号 + 白名单与改法，一行一项
    static func failureMessage(_ violations: [PermissionSourceHit]) -> String {
        var lines: [String] = []
        lines.append("❌ 权限判据越界：\(violations.count) 处直接调用了系统权限 API")
        lines.append("   这些文件不在白名单里，权限状态会出现第二个真相来源。")
        lines.append("")
        for hit in violations { lines.append("   • \(hit.readable)") }
        lines.append("")
        lines.append("白名单（加调用点前先读理由）：")
        for item in whitelist { lines.append("   · \(item.path) —— \(item.reason)") }
        lines.append("")
        lines.append("改法：转发 SystemPermissionCenter 发布的快照，不要在功能路径上自己再读一次。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 用例

/// 权限判据守卫 —— 纯判定矩阵 + 真实源码树扫描
func runPermissionSourceGuardTests() {
    print("\n🧪 Testing 权限判据守卫（权限判据只走 SystemPermissionCenter）...")

    // MARK: 纯判定：注释与字符串里的 API 名不算调用
    let commented = """
    // 这里说明 AXIsProcessTrusted 的语义，不是调用
    /* CGPreflightScreenCaptureAccess 只查不登记 */
    let text = "CGRequestScreenCaptureAccess 会弹一次系统提示"
    """
    assertEqual(PermissionSourceGuard.report(sources: ["Foo.swift": commented],
                                             whitelist: PermissionSourceGuard.whitelist),
                .compliant(usageByPath: [:]),
                "注释与字符串里的 API 名不算调用")

    // MARK: 纯判定：白名单内命中放行，并按文件给出命中次数
    let inWhitelist = """
    let a = AXIsProcessTrusted()
    let b = AXIsProcessTrusted()
    let c = CGPreflightScreenCaptureAccess()
    """
    assertEqual(PermissionSourceGuard.report(
                    sources: ["NetworkMonitorFeatureClipboard/ClipboardPaster.swift": inWhitelist],
                    whitelist: PermissionSourceGuard.whitelist),
                .compliant(usageByPath: ["NetworkMonitorFeatureClipboard/ClipboardPaster.swift": 3]),
                "白名单内命中放行并按文件计数")

    // MARK: 纯判定：白名单外命中给出文件与行号
    let outOfWhitelist = """
    import Foundation

    func check() -> Bool {
        AXIsProcessTrusted()
    }
    """
    assertEqual(PermissionSourceGuard.report(sources: ["Settings/SomePane.swift": outOfWhitelist],
                                             whitelist: PermissionSourceGuard.whitelist),
                .violations([PermissionSourceHit(path: "Settings/SomePane.swift",
                                                 line: 4,
                                                 symbol: "AXIsProcessTrusted")]),
                "白名单外命中：给出文件与行号")

    // 行号对齐：块注释跨行之后，真实调用的行号不漂移
    let afterBlockComment = """
    /* 第一行
       第二行 */
    CGRequestScreenCaptureAccess()
    """
    assertEqual(PermissionSourceGuard.hits(in: afterBlockComment, path: "X.swift"),
                [PermissionSourceHit(path: "X.swift", line: 3,
                                     symbol: "CGRequestScreenCaptureAccess")],
                "块注释跨行后行号仍与原文一致")

    // 同一行两处命中都要记
    let twoOnOneLine = "let a = AXIsProcessTrusted(); let b = CGPreflightScreenCaptureAccess()"
    assertEqual(PermissionSourceGuard.hits(in: twoOnOneLine, path: "Y.swift").count, 2,
                "同一行两处命中都记")

    // MARK: 真实源码树扫描
    guard let root = PermissionSourceGuard.sourceRoot() else {
        print("❌ 找不到源码根 Sources（#filePath 反推失败）")
        exit(1)
    }
    let sources = PermissionSourceGuard.loadSources(root: root)
    assertEqual(sources.isEmpty, false, "源码树非空（否则守卫形同虚设）")
    // TestRunner 排除：它的源码字符串夹具在字符串里嵌引号，会骗过扫描器
    let productSources = sources.filter { !$0.key.hasPrefix("TestRunner/") }

    switch PermissionSourceGuard.report(sources: productSources,
                                        whitelist: PermissionSourceGuard.whitelist) {
    case .compliant(let usage):
        // 白名单每一项都必须真的还在用这套 API：某一项变成 0 说明名单已过期，
        // 应当删掉，免得它继续为后来者提供豁免借口
        for item in PermissionSourceGuard.whitelist {
            assertNotNil(usage[item.path], "白名单项仍在使用：\(item.path)")
        }
        print("✅ 权限判据只走 SystemPermissionCenter（\(usage.count) 个白名单文件）")
    case .violations(let violations):
        print(PermissionSourceGuard.failureMessage(violations))
        exit(1)
    }
}
