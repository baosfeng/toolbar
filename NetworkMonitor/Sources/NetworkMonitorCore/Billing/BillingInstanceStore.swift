import Foundation

// MARK: - 实例列表持久化

/// provider 类型种子 —— 组合根把「已注册的类型」传给存储层，用来补齐默认实例
///
/// 只放纯数据（不含 provider 实例）：Core 不知道具体实现类怎么构造，
/// 具体 provider 的创建留在组合根，符合依赖倒置。
public struct BillingInstanceKindSeed: Sendable, Equatable {
    public let kindID: String
    /// 默认实例的展示名（通常等于 provider 的 displayName）
    public let title: String

    public init(kindID: String, title: String) {
        self.kindID = kindID
        self.title = title
    }
}

// MARK: - 纯变更函数

/// 实例列表的增删改 —— 纯函数，供存储层与 TestRunner 共用同一份规则
public enum BillingInstanceMutation {

    /// 补齐缺失的默认实例（幂等，保持已存顺序，新类型追加在末尾）
    ///
    /// 老用户升级路径：存储里没有 `billing.instances` 时返回的每个 kind 都只有默认实例，
    /// 而默认实例的 id 就是 kindID，旧凭据键 / 启用键原样命中 —— 零迁移。
    public static func filled(_ instances: [BillingInstance],
                              kinds: [BillingInstanceKindSeed]) -> [BillingInstance] {
        var result = instances
        let existingKinds = Set(instances.map(\.kindID))
        for kind in kinds where !existingKinds.contains(kind.kindID) {
            result.append(BillingInstanceID.defaultInstance(kindID: kind.kindID, title: kind.title))
        }
        return result
    }

    /// 新增命名实例
    public static func adding(_ instances: [BillingInstance],
                              kindID: String,
                              slug: String,
                              title: String) throws -> (list: [BillingInstance], instance: BillingInstance) {
        guard let instance = BillingInstanceID.namedInstance(kindID: kindID, slug: slug, title: title) else {
            throw BillingInstanceError.invalidSlug
        }
        let sameKind = instances.filter { $0.kindID == kindID }
        guard !sameKind.contains(where: { $0.slug == slug }) else {
            throw BillingInstanceError.duplicateSlug(slug)
        }
        return (instances + [instance], instance)
    }

    /// 重命名（只改展示名，不动 id，因此凭据与提醒状态都保留）
    public static func renaming(_ instances: [BillingInstance],
                                instanceID: String,
                                title: String) -> [BillingInstance] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return instances }
        return instances.map { $0.id == instanceID ? $0.renamed(trimmed) : $0 }
    }

    /// 删除实例（默认实例不可删）
    public static func removing(_ instances: [BillingInstance],
                                instanceID: String) throws -> [BillingInstance] {
        guard instances.contains(where: { $0.id == instanceID }) else {
            throw BillingInstanceError.notFound(instanceID)
        }
        guard !BillingInstanceID.isDefault(instanceID) else {
            throw BillingInstanceError.cannotRemoveDefault
        }
        return instances.filter { $0.id != instanceID }
    }
}

// MARK: - 存储

/// 实例列表存储 —— JSON 落 `KeyValueStorage`，与凭据（`SecretStorage`）/ 启用开关分开
///
/// 键 `billing.instances`：值为 `[BillingInstance]` 的 JSON。
/// 只存结构，不存凭据 —— 凭据仍走 `BillingCredentialStore`（密文）。
public struct BillingInstanceStore: Sendable {

    /// 存储键
    public static let storageKey = "billing.instances"

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 读取已存实例（未写过 / 解不出来时为空数组）
    public func load() -> [BillingInstance] {
        guard let data = storage.object(forKey: Self.storageKey) as? Data else { return [] }
        return (try? JSONDecoder().decode([BillingInstance].self, from: data)) ?? []
    }

    /// 写入实例列表
    public func save(_ instances: [BillingInstance]) {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        storage.set(data, forKey: Self.storageKey)
    }

    /// 读取并补齐默认实例（首次启动 / 新增 provider 类型时调用），必要时落盘
    @discardableResult
    public func ensureDefaults(kinds: [BillingInstanceKindSeed]) -> [BillingInstance] {
        let stored = load()
        let filled = BillingInstanceMutation.filled(stored, kinds: kinds)
        if filled != stored { save(filled) }
        return filled
    }

    /// 新增命名实例并落盘
    public func add(kindID: String, slug: String, title: String) throws -> BillingInstance {
        let (list, instance) = try BillingInstanceMutation.adding(load(), kindID: kindID,
                                                                  slug: slug, title: title)
        save(list)
        return instance
    }

    /// 重命名并落盘
    public func rename(instanceID: String, title: String) {
        save(BillingInstanceMutation.renaming(load(), instanceID: instanceID, title: title))
    }

    /// 删除并落盘
    public func remove(instanceID: String) throws {
        save(try BillingInstanceMutation.removing(load(), instanceID: instanceID))
    }
}
