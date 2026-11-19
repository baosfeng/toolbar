// MARK: - 面板分页模块描述符（纯值：无 AppKit、无闭包）

/// 一个面板分页的**去 AppKit 描述** —— 分段条文案 / 图标 / 快照后缀 / 取证标识的唯一真源
///
/// 为什么放在 UI 库：TestRunner 只能依赖 Core + UI，看不到 App 可执行目标；
/// 分段条文字、图标名、快照文件名后缀这些「口径」必须能被单测逐项断言，
/// 否则加一个分页又要靠人手核对四个穷尽 switch。
///
/// 与 App 侧 PaneModule 的分工（架构契约 §1）：本文件 = Descriptor（纯值、可测），
/// MenuPanel/PaneModule.swift = Module（Descriptor + 造页 / 挂动作闭包，留在 App target）。
public struct PaneModuleDescriptor: Sendable, Equatable {

    /// 稳定 id（必须 ∈ PanelTabCatalog.stableIDs）—— 偏好里存的就是它
    public let id: String
    /// 分页枚举的历史编号（Int rawValue，冻结不重排；与 PanelTabCatalog.legacyRawValueToStableID 同键）
    public let rawValue: Int
    /// 分段条文字
    public let title: String
    /// 分段条图标（SF Symbols，禁止 emoji）
    public let symbolName: String
    /// 快照文件名后缀
    public let snapshotSuffix: String
    /// 取证标识：NM_EVIDENCE_TAB 等环境变量的取值（历史上就是分页 id）
    public let evidenceKey: String
    /// 声明序 = 默认序（与 PanelTabCatalog.stableIDs 同序）
    public let sortIndex: Int

    public init(id: String,
                rawValue: Int,
                title: String,
                symbolName: String,
                snapshotSuffix: String,
                evidenceKey: String,
                sortIndex: Int) {
        self.id = id
        self.rawValue = rawValue
        self.title = title
        self.symbolName = symbolName
        self.snapshotSuffix = snapshotSuffix
        self.evidenceKey = evidenceKey
        self.sortIndex = sortIndex
    }

    /// 未登记的兜底值（分页枚举多了一个 case 却没进目录时用）
    ///
    /// 不用 preconditionFailure 让 release 直接崩：兜底值渲染成少一个图标的分段，
    /// 开发期由 assertionFailure 与 TestRunner 的注册表自洽断言兜住。
    public static func placeholder(rawValue: Int) -> PaneModuleDescriptor {
        PaneModuleDescriptor(id: "unregistered-\(rawValue)",
                             rawValue: rawValue,
                             title: "",
                             symbolName: "",
                             snapshotSuffix: "unregistered-\(rawValue)",
                             evidenceKey: "unregistered-\(rawValue)",
                             sortIndex: Int.max)
    }
}

// MARK: - 装配问题（注册表自洽判据）

/// 注册表与分页目录对不上时的具体问题 —— 漏登记时测试与启动日志都读这一份
public enum PaneModuleProblem: Equatable, Sendable, CustomStringConvertible {
    /// 同一稳定 id 注册了两次
    case duplicateID(String)
    /// 同一历史编号登记了两个分页
    case duplicateRawValue(Int)
    /// 快照后缀撞车（会覆盖彼此的取证图）
    case duplicateSnapshotSuffix(String)
    /// 取证标识撞车
    case duplicateEvidenceKey(String)
    /// id 不在 PanelTabCatalog.stableIDs 里
    case idNotInCatalog(String)
    /// 目录里有、注册表里没有
    case missingID(String)
    /// 集合一致但顺序不一致（分段条顺序会与数字键 / 键盘循环错位）
    case outOfOrder(expected: [String], actual: [String])

    public var description: String {
        switch self {
        case .duplicateID(let id): return "分页 id 重复：\(id)"
        case .duplicateRawValue(let rawValue): return "分页历史编号重复：\(rawValue)"
        case .duplicateSnapshotSuffix(let suffix): return "快照后缀重复：\(suffix)"
        case .duplicateEvidenceKey(let key): return "取证标识重复：\(key)"
        case .idNotInCatalog(let id): return "分页 id 不在目录里：\(id)"
        case .missingID(let id): return "分页未注册：\(id)"
        case .outOfOrder(let expected, let actual):
            let want = expected.joined(separator: "/")
            let got = actual.joined(separator: "/")
            return "分页顺序与目录不一致：期望 \(want)，实际 \(got)"
        }
    }
}

// MARK: - 分页描述符目录（唯一真源）

/// 五个分页的描述符 —— 分段条文案 / 图标 / 快照后缀 / 取证标识的唯一出处
///
/// 改造前这些散在 MenuTabBarView 的三个穷尽 switch、快照文件名后缀 switch 与
/// 取证环境变量映射里：改一处必须改四处，漏一处没有任何编译错误。
public enum PaneModuleCatalog {

    /// 全部分页描述符（顺序即声明序 = 默认序 = 数字键顺序）
    public static let descriptors: [PaneModuleDescriptor] = [
        PaneModuleDescriptor(id: "network",
                             rawValue: 0,
                             title: "网络",
                             symbolName: "network",
                             snapshotSuffix: "network",
                             evidenceKey: "network",
                             sortIndex: 0),
        PaneModuleDescriptor(id: "transfer",
                             rawValue: 2,
                             title: "传送",
                             symbolName: "paperplane",
                             snapshotSuffix: "transfer",
                             evidenceKey: "transfer",
                             sortIndex: 1),
        PaneModuleDescriptor(id: "credits",
                             rawValue: 3,
                             title: "额度",
                             symbolName: "creditcard",
                             snapshotSuffix: "credits",
                             evidenceKey: "credits",
                             sortIndex: 2),
        PaneModuleDescriptor(id: "token",
                             rawValue: 4,
                             title: "Token",
                             // macOS 14+（SF Symbols 5）可用；解析失败时仅少一个图标
                             symbolName: "chart.bar.xaxis",
                             snapshotSuffix: "token",
                             evidenceKey: "token",
                             sortIndex: 3),
        PaneModuleDescriptor(id: "system",
                             rawValue: 5,
                             title: "系统",
                             symbolName: "gauge.with.dots.needle.67percent",
                             snapshotSuffix: "system",
                             evidenceKey: "system",
                             sortIndex: 4),
    ]

    /// 按稳定 id 查描述符
    public static func descriptor(forID id: String) -> PaneModuleDescriptor? {
        descriptors.first { $0.id == id }
    }

    /// 按历史编号查描述符（分页枚举 rawValue → 描述符）
    public static func descriptor(forRawValue rawValue: Int) -> PaneModuleDescriptor? {
        descriptors.first { $0.rawValue == rawValue }
    }

    /// 按取证标识查描述符（NM_EVIDENCE_TAB 的取值）
    public static func descriptor(forEvidenceKey key: String) -> PaneModuleDescriptor? {
        descriptors.first { $0.evidenceKey == key }
    }

    /// 目录声明的 id 顺序
    public static var orderedIDs: [String] { descriptors.map(\.id) }

    /// 校验一组描述符是否自洽（正常 / 重复 / 缺项 / 顺序全走这一条判据）
    public static func validate(_ items: [PaneModuleDescriptor]) -> [PaneModuleProblem] {
        var problems: [PaneModuleProblem] = []

        // 1) 重复项：id / 历史编号 / 快照后缀 / 取证标识
        problems.append(contentsOf: duplicates(items.map(\.id)).map(PaneModuleProblem.duplicateID))
        problems.append(contentsOf: duplicates(items.map(\.rawValue)).map(PaneModuleProblem.duplicateRawValue))
        problems.append(contentsOf: duplicates(items.map(\.snapshotSuffix))
            .map(PaneModuleProblem.duplicateSnapshotSuffix))
        problems.append(contentsOf: duplicates(items.map(\.evidenceKey))
            .map(PaneModuleProblem.duplicateEvidenceKey))

        // 2) 与分页目录的集合一致性
        let expected = PanelTabCatalog.stableIDs
        let actual = items.sorted(by: sortByIndex).map(\.id)
        let actualSet = Set(actual)
        let expectedSet = Set(expected)
        for id in expected where !actualSet.contains(id) { problems.append(.missingID(id)) }
        for id in actual where !expectedSet.contains(id) { problems.append(.idNotInCatalog(id)) }

        // 3) 顺序一致性（集合一致时才判顺序，否则会与缺项重复报）
        if actualSet == expectedSet, actual != expected {
            problems.append(.outOfOrder(expected: expected, actual: actual))
        }
        return problems
    }

    /// 默认排序：sortIndex 升序，同序时按 id 稳定兜底
    public static func sortByIndex(_ lhs: PaneModuleDescriptor, _ rhs: PaneModuleDescriptor) -> Bool {
        lhs.sortIndex == rhs.sortIndex ? lhs.id < rhs.id : lhs.sortIndex < rhs.sortIndex
    }

    /// 找出重复出现的值（保持首次重复的先后顺序）
    private static func duplicates<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var repeated: [T] = []
        var repeatedSet = Set<T>()
        for value in values {
            if seen.contains(value) {
                if repeatedSet.insert(value).inserted { repeated.append(value) }
            } else {
                seen.insert(value)
            }
        }
        return repeated
    }
}

// MARK: - 分页注册表（纯描述符；App 侧装配件按 id 挂工厂闭包）

/// 分页描述符注册表 —— register 一处登记，分段条 / 快照 / 取证全部从这里读
///
/// 唯一性以**稳定 id** 为键：同 id 重复注册 = 替换（沿用 BillingProviderRegistry 的既有语义），
/// 返回值告诉调用方这次是新增还是覆盖 —— 覆盖往往是重复装配的信号。
public struct PaneDescriptorRegistry {

    private var storage: [String: PaneModuleDescriptor] = [:]

    /// 空注册表（测试 / 未装配场景）
    public init() {}

    /// 以一组描述符初始化
    public init(descriptors: [PaneModuleDescriptor]) {
        for descriptor in descriptors { register(descriptor) }
    }

    /// 注册一个分页描述符；返回 true = 新增，false = 覆盖同 id 的旧项
    @discardableResult
    public mutating func register(_ descriptor: PaneModuleDescriptor) -> Bool {
        let isNew = storage[descriptor.id] == nil
        storage[descriptor.id] = descriptor
        return isNew
    }

    /// 全部描述符（按 sortIndex 排序 = 声明序）
    public var all: [PaneModuleDescriptor] {
        storage.values.sorted(by: PaneModuleCatalog.sortByIndex)
    }

    /// 按稳定 id 查描述符
    public func descriptor(forID id: String) -> PaneModuleDescriptor? { storage[id] }

    /// 按历史编号查描述符
    public func descriptor(forRawValue rawValue: Int) -> PaneModuleDescriptor? {
        all.first { $0.rawValue == rawValue }
    }

    /// 按取证标识查描述符
    public func descriptor(forEvidenceKey key: String) -> PaneModuleDescriptor? {
        all.first { $0.evidenceKey == key }
    }

    /// 注册表与分页目录是否自洽（空数组 = 自洽）
    public func validate() -> [PaneModuleProblem] { PaneModuleCatalog.validate(all) }

    /// 用目录全量装配 —— 组合根与测试共用同一条装配路径
    public static func registeringCatalog() -> PaneDescriptorRegistry {
        PaneDescriptorRegistry(descriptors: PaneModuleCatalog.descriptors)
    }
}
