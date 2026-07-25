import Foundation

// MARK: - 键值存储

/// 键值存储 — 抽象 UserDefaults / 测试 Mock
///
/// 替代直接使用 `UserDefaults.standard`，使代码可测试
public protocol KeyValueStorage: AnyObject, Sendable {
    func integer(forKey key: String) -> Int
    func double(forKey key: String) -> Double
    func bool(forKey key: String) -> Bool
    func string(forKey key: String) -> String?
    func object(forKey key: String) -> Any?
    func array(forKey key: String) -> [Any]?

    func set(_ value: Int, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: String, forKey key: String)
    func set(_ value: Any?, forKey key: String)

    func removeObject(forKey key: String)
}

