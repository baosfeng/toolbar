import Foundation

// MARK: - UserDefaults 键值存储实现

/// 基于 UserDefaults 的键值存储实现
public final class UserDefaultsStorage: @unchecked Sendable, KeyValueStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    public func double(forKey key: String) -> Double { defaults.double(forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    public func array(forKey key: String) -> [Any]? { defaults.array(forKey: key) }

    public func set(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }

    public func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}
