import Foundation

// MARK: - 断言辅助

// 手写断言：失败即 exit(1)，供 TestRunner 各测试文件共用。

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ \(expected)", message.isEmpty ? "" : " — \(message)")
    } else {
        print("❌ \(file):\(line) — expected \"\(expected)\", got \"\(actual)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        print("✅ \(message.isEmpty ? "not nil" : message)")
    } else {
        print("❌ \(file):\(line) — expected not nil\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertContains(_ haystack: String, _ needle: String, _ message: String = "", file: String = #file, line: Int = #line) {
    if haystack.contains(needle) {
        print("✅ 包含 \"\(needle)\"", message.isEmpty ? "" : " — \(message)")
    } else {
        print("❌ \(file):\(line) — 期望包含 \"\(needle)\"，实际 \"\(haystack)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertNotContains(_ haystack: String, _ needle: String, _ message: String = "", file: String = #file, line: Int = #line) {
    if !haystack.contains(needle) {
        print("✅ 不含 \"\(needle)\"", message.isEmpty ? "" : " — \(message)")
    } else {
        print("❌ \(file):\(line) — 意外包含 \"\(needle)\"：\"\(haystack)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}
