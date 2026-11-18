import Foundation

// MARK: - 设置项顺序偏好键名

/// 设置项自定义排序的偏好键名 —— 写入、读取、迁移与测试共用同一份定义
///
/// 键名集中：避免「设置页写了一个键、消费方读的是另一个键」这类「设了不生效」的故障。
public enum SettingsOrderKey {
    /// 菜单栏指标上屏顺序（逗号分隔的指标 rawValue）
    public static let menuBarMetrics = "settings.order.menuBar.metrics"
    /// 面板分页顺序（逗号分隔的稳定 id；旧键 `panel.tabs.order` 存的是 Int rawValue，需一次性迁移）
    public static let panelTabs = "settings.order.panelTabs"
}

// MARK: - 顺序列表编解码

/// 顺序列表的编解码与整理 —— 编码口径与 `SnipToolBarListCoding` 一致（逗号分隔字符串）
///
/// 三条规则：
/// 1. 缺键 / 空串 → 默认顺序（读路径不写回：默认值将来变了，没设置过的用户跟着变）
/// 2. 未知 id 丢弃、重复 id 只留第一次出现（旧版本或手工改坏的数据不整份丢）
/// 3. 已知项缺失时按 `defaultOrder` 补到末尾（新增设置项既不丢，也不会打乱已有排序）
public enum SettingsOrderCoding {

    /// 解码：按逗号切分、去空白、丢空项
    public static func decode(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 编码：按给定顺序拼成逗号分隔串
    public static func encode(_ ids: [String]) -> String {
        ids.joined(separator: ",")
    }

    /// 整理成合法顺序：去未知、去重（保首次）、缺失按 `defaultOrder` 补尾
    ///
    /// - Parameters:
    ///   - ids: 存储里的原始顺序
    ///   - known: 当前版本全部合法 id
    ///   - defaultOrder: 默认顺序（须覆盖 `known`；未覆盖的项按 `known` 顺序补尾兜底）
    public static func normalize(_ ids: [String],
                                 known: [String],
                                 defaultOrder: [String]) -> [String] {
        let knownSet = Set(known)
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where knownSet.contains(id) {
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        for id in defaultOrder where knownSet.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        for id in known where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }
}

// MARK: - 顺序偏好读写

/// 顺序偏好的读写门面 —— 缺键回落默认，且**不写回**
///
/// 迁移场景（旧格式转新格式）才回写，由调用方显式执行，避免「读一次就把默认值固化成用户选择」。
public enum SettingsOrderStore {

    /// 读当前顺序；无键 / 空串 / 全非法时返回整理后的默认顺序
    public static func order(forKey key: String,
                             known: [String],
                             defaultOrder: [String],
                             storage: any KeyValueStorage) -> [String] {
        let stored = SettingsOrderCoding.decode(storage.string(forKey: key))
        let normalized = SettingsOrderCoding.normalize(stored, known: known, defaultOrder: defaultOrder)
        return normalized.isEmpty ? defaultOrder : normalized
    }

    /// 写顺序（调用方负责传整理后的列表）
    public static func save(_ ids: [String], forKey key: String, storage: any KeyValueStorage) {
        storage.set(SettingsOrderCoding.encode(ids), forKey: key)
    }

    /// 恢复默认：删键（下次读回落代码默认顺序）
    public static func reset(forKey key: String, storage: any KeyValueStorage) {
        storage.removeObject(forKey: key)
    }

    /// 移动一项：`offset` = -1 上移 / +1 下移；越界时原样返回
    public static func moved(_ order: [String], id: String, offset: Int) -> [String] {
        guard let index = order.firstIndex(of: id) else { return order }
        let target = index + offset
        guard order.indices.contains(target) else { return order }
        var next = order
        next.swapAt(index, target)
        return next
    }
}

// MARK: - 排序移动口径

/// 可排序卡片的「怎么动」口径 —— 默认整列自由换序，分组场景只允许组内换序
///
/// 通用组件（SettingsOrderedCardView）只负责画行与上移 / 下移按钮，
/// 「能不能动、动了以后长什么样」交给这里：
/// - 默认口径 free 与改造前完全一致（整列可换序、越界不动）；
/// - 贴图右键菜单用分组口径（PinMenuOrderResolver.movePolicy）：跨组与危险组一律拒绝，
///   于是「销毁」永远拿不到可用的上移按钮。
///
/// normalize 也放在这里：卡片读偏好的归一口径必须与消费方一致，
/// 否则设置页看到的顺序和真正上屏的顺序会分叉。
public struct SettingsOrderMovePolicy: Sendable {

    /// 整理顺序：(原始 ids, 全部合法 id, 默认顺序) → 合法顺序
    public typealias Normalizer = @Sendable ([String], [String], [String]) -> [String]
    /// 移动一项：(当前顺序, 行 id, ±1) → 新顺序；拒绝时原样返回
    public typealias Mover = @Sendable ([String], String, Int) -> [String]
    /// 能否移动：(当前顺序, 行下标, ±1) → 是否启用按钮
    public typealias CanMove = @Sendable ([String], Int, Int) -> Bool

    public let normalize: Normalizer
    public let move: Mover
    public let canMove: CanMove

    public init(normalize: @escaping Normalizer, move: @escaping Mover, canMove: @escaping CanMove) {
        self.normalize = normalize
        self.move = move
        self.canMove = canMove
    }

    /// 默认口径：整列自由换序（指标 / 分页 / 工具条组与动作都用它）
    public static let free = SettingsOrderMovePolicy(
        normalize: { SettingsOrderCoding.normalize($0, known: $1, defaultOrder: $2) },
        move: { SettingsOrderStore.moved($0, id: $1, offset: $2) },
        canMove: { order, index, offset in
            order.indices.contains(index) && order.indices.contains(index + offset)
        })
}

// MARK: - 旧格式迁移

/// 旧「Int rawValue 逗号串」格式的迁移判据
///
/// 分页顺序早期存的是 `MenuPanelTab.rawValue`（Int，按声明位置编号）：
/// 将来在枚举中间插入一个分页，旧偏好里的数字会指向另一页。迁移成稳定 id 后不再有这个问题。
public enum SettingsOrderLegacy {

    /// 把旧 Int 串翻译成新稳定 id 顺序
    ///
    /// - Parameters:
    ///   - raw: 旧键原始串；nil / 空串返回 nil（调用方据此判断「没有旧数据」）
    ///   - legacyIDs: 旧 Int → 稳定 id 的映射表
    ///   - known: 当前版本全部合法 id
    ///   - defaultOrder: 默认顺序
    /// - Returns: 已整理的顺序；nil = 没有可迁移的旧数据
    public static func migrateIntOrder(_ raw: String?,
                                       legacyIDs: [Int: String],
                                       known: [String],
                                       defaultOrder: [String]) -> [String]? {
        guard let raw, !raw.isEmpty else { return nil }
        let ids = raw.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .compactMap { legacyIDs[$0] }
        guard !ids.isEmpty else { return nil }
        return SettingsOrderCoding.normalize(ids, known: known, defaultOrder: defaultOrder)
    }
}

