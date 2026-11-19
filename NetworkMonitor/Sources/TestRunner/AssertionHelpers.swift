import Foundation

// MARK: - 断言辅助

// 手写断言：失败**累计**、套件跑完在 `TestAssertions.finish()` 统一 exit(1)，
// 供 TestRunner 各测试文件共用。
//
// 改造前是「首错即停（exit(1)）」：一次只能看到一个红，修一条跑一次全量。
// 现在一次运行能看到全部 ❌，输出行格式（✅ / ❌ 行）与逐字文案保持不变。

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ \(expected)", message.isEmpty ? "" : " — \(message)")
    } else {
        let detail = "\(file):\(line) — expected \"\(expected)\", got \"\(actual)\"\(message.isEmpty ? "" : " — \(message)")"
        print("❌ \(detail)")
        TestAssertions.recordFailure(detail)
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        print("✅ \(message.isEmpty ? "not nil" : message)")
    } else {
        let detail = "\(file):\(line) — expected not nil\(message.isEmpty ? "" : " — \(message)")"
        print("❌ \(detail)")
        TestAssertions.recordFailure(detail)
    }
}

func assertContains(_ haystack: String, _ needle: String, _ message: String = "", file: String = #file, line: Int = #line) {
    if haystack.contains(needle) {
        print("✅ 包含 \"\(needle)\"", message.isEmpty ? "" : " — \(message)")
    } else {
        let detail = "\(file):\(line) — 期望包含 \"\(needle)\"，实际 \"\(haystack)\"\(message.isEmpty ? "" : " — \(message)")"
        print("❌ \(detail)")
        TestAssertions.recordFailure(detail)
    }
}

func assertNotContains(_ haystack: String, _ needle: String, _ message: String = "", file: String = #file, line: Int = #line) {
    if !haystack.contains(needle) {
        print("✅ 不含 \"\(needle)\"", message.isEmpty ? "" : " — \(message)")
    } else {
        let detail = "\(file):\(line) — 意外包含 \"\(needle)\"：\"\(haystack)\"\(message.isEmpty ? "" : " — \(message)")"
        print("❌ \(detail)")
        TestAssertions.recordFailure(detail)
    }
}
