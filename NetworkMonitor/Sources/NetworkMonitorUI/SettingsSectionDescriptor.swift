// MARK: - 设置分类模块描述符（纯值：无 AppKit、无闭包）

/// 一个设置分类的**去 AppKit 描述** —— 侧栏标题 / 图标 / 页头副标题 / 快照后缀的唯一真源
///
/// 改造前这四项散在 SettingsSection 的四个穷尽 switch 里（title / symbolName /
/// fileSuffix / subtitle）：加一个分类要改四处，漏一处没有编译错误，只会静默少一段文案。
///
/// 与 App 侧 SettingsModule 的分工（架构契约 §1）：本文件 = Descriptor（纯值、可测），
/// Settings/SettingsModule.swift = Module（Descriptor + 造页闭包，留在 App target）。
public struct SettingsSectionDescriptor: Sendable, Equatable {

    /// 分类 id（与 App 侧 SettingsSection 的 case 同名同序）
    public let id: SettingsSectionID
    /// 侧栏与页头标题
    public let title: String
    /// SF Symbols 图标名（禁止 emoji）
    public let symbolName: String
    /// 页头副标题（一句话说明这一页管什么）
    public let subtitle: String
    /// 快照文件名后缀（仅 DEBUG 自证用）
    public let fileSuffix: String
    /// 侧栏分组归属
    public let group: SettingsSidebarSegment

    public init(id: SettingsSectionID,
                title: String,
                symbolName: String,
                subtitle: String,
                fileSuffix: String,
                group: SettingsSidebarSegment) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.subtitle = subtitle
        self.fileSuffix = fileSuffix
        self.group = group
    }

    /// 未登记的兜底描述（分类枚举多了一个 case 却没进目录时用）
    public static func placeholder(id: SettingsSectionID) -> SettingsSectionDescriptor {
        SettingsSectionDescriptor(id: id,
                                  title: id.rawValue,
                                  symbolName: "",
                                  subtitle: "",
                                  fileSuffix: id.rawValue,
                                  group: .feature)
    }
}

// MARK: - 装配问题（注册表自洽判据）

/// 注册表与分类目录对不上时的具体问题
public enum SettingsSectionProblem: Equatable, Sendable, CustomStringConvertible {
    /// 同一分类登记了两次
    case duplicateID(String)
    /// 快照后缀撞车
    case duplicateFileSuffix(String)
    /// 目录里有、注册表里没有
    case missingID(String)
    /// 集合一致但顺序不一致（侧栏与切页顺序会错位）
    case outOfOrder(expected: [String], actual: [String])
    /// 侧栏分组与 SettingsSidebarLayout 不一致（同一页会出现在两条不同路径上）
    case groupMismatch(id: String, expected: String, actual: String)

    public var description: String {
        switch self {
        case .duplicateID(let id): return "设置分类 id 重复：\(id)"
        case .duplicateFileSuffix(let suffix): return "设置快照后缀重复：\(suffix)"
        case .missingID(let id): return "设置分类未注册：\(id)"
        case .outOfOrder(let expected, let actual):
            return "设置分类顺序与目录不一致：期望 \(expected.joined(separator: ","))，实际 \(actual.joined(separator: ","))"
        case .groupMismatch(let id, let expected, let actual):
            return "设置分类 \(id) 的侧栏分组不一致：侧栏是 \(expected)，描述符是 \(actual)"
        }
    }
}

// MARK: - 设置分类目录（唯一真源）

/// 十一个设置分类的描述符 —— 侧栏文案 / 图标 / 页头副标题 / 快照后缀的唯一出处
public enum SettingsSectionCatalog {

    /// 全部分类描述符（顺序即声明序 = 侧栏顺序）
    public static let descriptors: [SettingsSectionDescriptor] = [
        SettingsSectionDescriptor(id: .general,
                                  title: "通用",
                                  symbolName: "gearshape",
                                  subtitle: "启动行为、额度提醒、面板通知与显示排序。",
                                  fileSuffix: "general",
                                  group: .general),
        SettingsSectionDescriptor(id: .appearance,
                                  title: "外观",
                                  symbolName: "paintpalette",
                                  subtitle: "主题、玻璃拟态与渲染帧率档。",
                                  fileSuffix: "appearance",
                                  group: .general),
        SettingsSectionDescriptor(id: .providers,
                                  title: "额度 Provider",
                                  symbolName: "creditcard",
                                  subtitle: "启用开关只影响查询与额度页展示，凭据继续保留；三类额度通知也在这里调。",
                                  fileSuffix: "providers",
                                  group: .feature),
        SettingsSectionDescriptor(id: .clipboard,
                                  title: "剪贴板",
                                  symbolName: "doc.on.clipboard",
                                  subtitle: "面板唤起、采集范围、操作通知与系统权限。",
                                  fileSuffix: "clipboard",
                                  group: .feature),
        SettingsSectionDescriptor(id: .capture,
                                  title: "截图与贴图",
                                  symbolName: "camera.viewfinder",
                                  subtitle: "截图、标注、贴图与截图完成通知的默认参数。",
                                  fileSuffix: "capture",
                                  group: .feature),
        SettingsSectionDescriptor(id: .transfer,
                                  title: "局域网互传",
                                  symbolName: "arrow.left.arrow.right",
                                  subtitle: "接收目录、免配对窗口与传输完成通知。",
                                  fileSuffix: "transfer",
                                  group: .feature),
        SettingsSectionDescriptor(id: .notifications,
                                  title: "通知与音效",
                                  symbolName: "bell.badge",
                                  subtitle: "通知权限、应用内音量与音效库；事件行已跟随功能页。",
                                  fileSuffix: "notifications",
                                  group: .feature),
        SettingsSectionDescriptor(id: .token,
                                  title: "Token 用量",
                                  symbolName: "chart.bar.doc.horizontal",
                                  subtitle: "各编码 agent 的本地会话目录（DSH / Claude Code / Codex / Gemini CLI / Copilot CLI / OpenCode / Zed）、解压工具探测与索引维护（重新扫描 / 清理历史数据）。",
                                  fileSuffix: "token",
                                  group: .feature),
        SettingsSectionDescriptor(id: .permissions,
                                  title: "系统权限",
                                  symbolName: "lock.shield",
                                  subtitle: "五类系统授权集中在这里：读到什么、能不能直接请求、授权后要不要重启，只有这一个口径。",
                                  fileSuffix: "permissions",
                                  group: .system),
        SettingsSectionDescriptor(id: .system,
                                  title: "系统",
                                  symbolName: "gauge.with.dots.needle.67percent",
                                  subtitle: "采样周期与面板显示项。",
                                  fileSuffix: "system",
                                  group: .system),
        SettingsSectionDescriptor(id: .about,
                                  title: "关于",
                                  symbolName: "info.circle",
                                  subtitle: "版本信息与项目地址。",
                                  fileSuffix: "about",
                                  group: .system),
    ]

    /// 按分类 id 查描述符
    public static func descriptor(for id: SettingsSectionID) -> SettingsSectionDescriptor? {
        descriptors.first { $0.id == id }
    }

    /// 目录声明的分类顺序（rawValue 串）
    public static var orderedIDs: [String] { descriptors.map { $0.id.rawValue } }

    /// 校验一组描述符是否自洽（重复 / 缺项 / 顺序 / 分组归属）
    public static func validate(_ items: [SettingsSectionDescriptor]) -> [SettingsSectionProblem] {
        var problems: [SettingsSectionProblem] = []

        problems.append(contentsOf: duplicates(items.map { $0.id.rawValue })
            .map(SettingsSectionProblem.duplicateID))
        problems.append(contentsOf: duplicates(items.map(\.fileSuffix))
            .map(SettingsSectionProblem.duplicateFileSuffix))

        let expected = SettingsSectionID.allCases.map { $0.rawValue }
        let actual = items.map { $0.id.rawValue }
        let actualSet = Set(actual)
        let expectedSet = Set(expected)
        for id in expected where !actualSet.contains(id) { problems.append(.missingID(id)) }
        if actualSet == expectedSet, actual != expected {
            problems.append(.outOfOrder(expected: expected, actual: actual))
        }

        // 分组归属必须与侧栏分组表一致：否则同一页会出现在两条不同路径上
        for item in items {
            guard let segment = SettingsSidebarLayout.segment(of: item.id) else { continue }
            if segment != item.group {
                problems.append(.groupMismatch(id: item.id.rawValue,
                                               expected: segment.rawValue,
                                               actual: item.group.rawValue))
            }
        }
        return problems
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

// MARK: - 设置分类注册表（纯描述符）

/// 设置分类描述符注册表 —— 同 id 重复注册 = 替换
public struct SettingsDescriptorRegistry {

    private var storage: [SettingsSectionID: SettingsSectionDescriptor] = [:]

    public init() {}

    public init(descriptors: [SettingsSectionDescriptor]) {
        for descriptor in descriptors { register(descriptor) }
    }

    /// 注册一个分类描述符；返回 true = 新增，false = 覆盖同 id 的旧项
    @discardableResult
    public mutating func register(_ descriptor: SettingsSectionDescriptor) -> Bool {
        let isNew = storage[descriptor.id] == nil
        storage[descriptor.id] = descriptor
        return isNew
    }

    /// 全部描述符（按目录声明序）
    public var all: [SettingsSectionDescriptor] {
        SettingsSectionCatalog.descriptors.compactMap { storage[$0.id] }
    }

    /// 按分类 id 查描述符
    public func descriptor(for id: SettingsSectionID) -> SettingsSectionDescriptor? { storage[id] }

    /// 注册表与分类目录是否自洽（空数组 = 自洽）
    public func validate() -> [SettingsSectionProblem] { SettingsSectionCatalog.validate(all) }

    /// 用目录全量装配 —— 组合根与测试共用同一条装配路径
    public static func registeringCatalog() -> SettingsDescriptorRegistry {
        SettingsDescriptorRegistry(descriptors: SettingsSectionCatalog.descriptors)
    }
}
