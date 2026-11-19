import Foundation

// MARK: - 套件登记守卫（孤儿测试文件检测）

/// 套件登记守卫 —— 新增测试文件忘了登记时判红
///
/// 背景：TestRunner 没有反射，入口只能在 `TestSuites+<域>.swift` 里逐行调用。
/// 忘了登记不会编译失败、也不会报错，测试**静默不跑**——这比「首错即停」更隐蔽。
/// 本守卫把「登记表必须自洽」变成一条机器判据，不靠人记。
///
/// 口径：`func run*Tests` 的定义，在整个 TestRunner 目录内至少要被**调用一次**
/// （定义行本身不算调用行）。由上层套件内部调用的（如 `ClipboardCapacityTests` 末尾
/// 调 `runCapacityByteCountTests()`）也算被调用，不误报。
///
/// 已知边界：只做文本扫描，不解析语法树。把函数名写进字符串、或用 `#if` 条件编译
/// 掉的场景看不见——那类改动请人工确认。
func runTestSuiteRegistrationTests() {
    print("🧪 Testing 测试套件登记（孤儿测试文件 / 每域登记函数齐全）...")

    let testRunnerDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    guard let enumerator = FileManager.default.enumerator(at: testRunnerDirectory,
                                                          includingPropertiesForKeys: nil) else {
        assertNotNil(nil as [Int]?, "读不到 TestRunner 源码目录：\(testRunnerDirectory.path)")
        return
    }

    // 本文件自身含「函数名 + 括号」的字面量，扫进来会把自己的示例当调用
    let selfFileName = "TestSuiteRegistrationTests.swift"
    let definitionPattern = try? NSRegularExpression(pattern: #"^\s*(?:@\w+\s+)*func\s+(run[A-Za-z0-9_]*Tests)\s*\("#)
    let anyNamePattern = try? NSRegularExpression(pattern: #"(run[A-Za-z0-9_]*(?:Tests|Suites))\b"#)

    var definitions: [String: String] = [:]   // 定义名 → 文件
    var callCounts: [String: Int] = [:]       // 名字 → 出现在非定义行的次数
    var scanned = 0

    for case let url as URL in enumerator where url.pathExtension == "swift" {
        guard url.lastPathComponent != selfFileName else { continue }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
        scanned += 1

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let definitionPattern,
               let match = definitionPattern.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line) {
                let name = String(line[nameRange])
                definitions[name] = url.lastPathComponent
                continue
            }

            // 注释行不算调用（说明文字里提到函数名很常见）
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            anyNamePattern?.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let match, let nameRange = Range(match.range(at: 1), in: line) else { return }
                callCounts[String(line[nameRange]), default: 0] += 1
            }
        }
    }

    assertEqual(scanned > 100, true, "扫描到 TestRunner 全部 .swift（实际 \(scanned) 个）")
    assertEqual(definitions.isEmpty, false, "能识别出 run*Tests 定义")

    let orphans = definitions.filter { callCounts[$0.key, default: 0] == 0 }.keys.sorted()
    assertEqual(orphans.count, 0,
                "没有孤儿测试函数（定义了却没有任何调用 = 静默不跑）；命中：\(orphans.joined(separator: ", "))")

    // 每域登记函数必须由 main.swift 调起，否则整域静默不跑
    for domain in ["Core", "Clipboard", "Snip", "Billing", "Token", "Pane", "System", "Transfer"] {
        let entry = "run\(domain)Suites"
        assertEqual(callCounts[entry, default: 0] > 0, true, "\(entry) 已被 main.swift 调起")
    }

    print("✅ 测试套件登记 works")
}
