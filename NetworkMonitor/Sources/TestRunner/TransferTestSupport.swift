import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · 测试辅助

// 断言与内存存储放宽为 internal：入口 runTransferTests() 位于 TransferTests.swift，
// 且集成 / 策略测试文件需跨文件复用，private 的文件作用域会使其不可见。

// MARK: - 断言辅助

/// 断言抛出指定业务错误码的传输域异常
func assertThrows(_ message: String, code expected: Int, _ body: () throws -> Void) {
    do {
        try body()
        print("❌ \(message) — 未抛出异常")
        exit(1)
    } catch let error as TransferError {
        assertEqual(error.code, expected, message)
    } catch {
        print("❌ \(message) — 抛出了非 TransferError：\(error)")
        exit(1)
    }
}

// MARK: - 集成 / 策略场景共享

// 放宽为 internal：集成测试与策略服务测试分处两个文件，均需构造与读取该场景类型。

/// 后台场景失败信息（跨线程传递）
final class ScenarioFailureBox: @unchecked Sendable {
    var message: String?
}

enum ScenarioError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

// MARK: - 配对记忆

/// 内存键值存储（隔离 UserDefaults，不污染本机偏好）
final class InMemoryStorage: KeyValueStorage, @unchecked Sendable {
    private var values: [String: Any] = [:]

    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func string(forKey key: String) -> String? { values[key] as? String }
    func object(forKey key: String) -> Any? { values[key] }
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }

    func set(_ value: Int, forKey key: String) { values[key] = value }
    func set(_ value: Double, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
