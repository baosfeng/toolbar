import Foundation

// MARK: - 额度 provider 实例

/// 一个额度实例 —— 同一 provider 类型（kind）可以有多份独立配置
///
/// 两类实例：
/// - **默认实例**：`id == kindID`（如 `cursor`）。旧版本的凭据键 `billing.credential.<kindID>`、
///   启用键 `billing.enabled.<kindID>`、提醒状态键 `<kindID>.<resourceID>` 全部原样命中，
///   因此升级不需要任何迁移；
/// - **命名实例**：`id == "cursor::work"`（`kindID` + 分隔符 + 用户命名后缀），各自独立配置与提醒。
public struct BillingInstance: Sendable, Equatable, Codable, Identifiable {
    /// 实例稳定标识（凭据键 / 启用键 / 提醒键都用它）
    public let id: String
    /// provider 类型标识（`cursor` / `codex` / `claude` / `ollama` …）
    public let kindID: String
    /// 展示名称（额度卡标题 / 设置页行名）
    public let title: String

    public init(id: String, kindID: String, title: String) {
        self.id = id
        self.kindID = kindID
        self.title = title
    }

    /// 是否默认实例（id 与 kindID 相同）
    public var isDefault: Bool { BillingInstanceID.isDefault(id) }

    /// 用户命名后缀（默认实例为 nil）
    public var slug: String? { BillingInstanceID.slug(of: id) }

    /// 改名（id 不变，避免动到凭据键）
    public func renamed(_ newTitle: String) -> BillingInstance {
        BillingInstance(id: id, kindID: kindID, title: newTitle)
    }
}

// MARK: - 实例标识规则（纯函数）

/// 实例标识的构造与解析 —— 标识规则只在这里定义一次，供存储、注册表、测试共用
///
/// 分隔符用 `::`：与 `billing.credential.` / `billing.enabled.` 前缀不冲突，
/// 且「某 kind 的全部实例」可以用前缀唯一识别。
public enum BillingInstanceID {

    /// 类型与实例名的分隔符
    public static let separator = "::"

    /// 命名后缀最大长度（过长会让设置页行名与键名都难读）
    public static let maxSlugLength = 24

    /// 构造实例标识：`slug` 为 nil 时返回默认实例标识（即 kindID）
    public static func make(kindID: String, slug: String?) -> String {
        guard let slug, !slug.isEmpty else { return kindID }
        return kindID + separator + slug
    }

    /// 取实例标识里的 provider 类型
    public static func kind(of instanceID: String) -> String {
        guard let range = instanceID.range(of: separator) else { return instanceID }
        return String(instanceID[instanceID.startIndex..<range.lowerBound])
    }

    /// 取实例标识里的命名后缀（默认实例为 nil）
    public static func slug(of instanceID: String) -> String? {
        guard let range = instanceID.range(of: separator) else { return nil }
        let slug = String(instanceID[range.upperBound...])
        return slug.isEmpty ? nil : slug
    }

    /// 是否默认实例（标识里不含分隔符）
    public static func isDefault(_ instanceID: String) -> Bool {
        !instanceID.contains(separator)
    }

    /// 命名后缀是否合法：小写字母 / 数字 / 连字符，且以字母或数字开头
    public static func isValidSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.count <= maxSlugLength else { return false }
        guard let first = slug.first, first.isLowercase || first.isNumber else { return false }
        return slug.allSatisfy { ($0.isLowercase && $0.isLetter) || $0.isNumber || $0 == "-" }
    }

    /// 环境变量回退键
    ///
    /// 默认实例沿用旧规则 `BILLING_<KIND>_API_KEY`（`opencode-go` → `BILLING_OPENCODE_GO_API_KEY`）；
    /// 命名实例追加后缀 `BILLING_<KIND>_<SLUG>_API_KEY`，保证每个实例都能单独 `export`。
    public static func environmentKey(kindID: String, slug: String?) -> String {
        var parts = [sanitized(kindID)]
        if let slug, !slug.isEmpty { parts.append(sanitized(slug)) }
        parts.append("API_KEY")
        return "BILLING_" + parts.joined(separator: "_")
    }

    /// 默认实例
    public static func defaultInstance(kindID: String, title: String) -> BillingInstance {
        BillingInstance(id: kindID, kindID: kindID, title: title)
    }

    /// 命名实例（后缀非法时返回 nil，由调用方决定如何提示）
    public static func namedInstance(kindID: String, slug: String, title: String) -> BillingInstance? {
        guard isValidSlug(slug) else { return nil }
        return BillingInstance(id: make(kindID: kindID, slug: slug),
                               kindID: kindID,
                               title: title.isEmpty ? "\(kindID)（\(slug)）" : title)
    }

    /// 键名清洗：大写 + 非字母数字一律换成下划线
    private static func sanitized(_ raw: String) -> String {
        raw.uppercased().map { ($0.isLetter || $0.isNumber) ? $0 : "_" }.reduce(into: "") { $0.append($1) }
    }
}

// MARK: - 实例错误

/// 实例增删改的错误 —— 按领域归类，调用方直接给用户看 `userMessage`
public enum BillingInstanceError: Error, Sendable, Equatable {
    /// 命名后缀不合法
    case invalidSlug
    /// 同一 provider 类型下后缀重复
    case duplicateSlug(String)
    /// 默认实例不允许删除（删掉等于让老配置失去落点）
    case cannotRemoveDefault
    /// 实例不存在
    case notFound(String)

    public var userMessage: String {
        switch self {
        case .invalidSlug:
            return "实例名只能用 1–\(BillingInstanceID.maxSlugLength) 个小写字母、数字或连字符"
        case .duplicateSlug(let slug):
            return "已存在同名实例「\(slug)」"
        case .cannotRemoveDefault:
            return "默认实例不能删除，可先停用它"
        case .notFound(let id):
            return "实例不存在：\(id)"
        }
    }
}
