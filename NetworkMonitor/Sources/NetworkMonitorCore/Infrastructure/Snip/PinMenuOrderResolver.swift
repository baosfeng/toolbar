import Foundation

// MARK: - 贴图菜单偏好键名

/// 贴图右键菜单的偏好键名
///
/// 与截图工具条同理：键名只在这里定义一次，设置页写入、贴图窗读取、测试断言共用，
/// 避免「设置页写了一个键、贴图窗读的是另一个键」这类「设了不生效」的故障。
public enum PinMenuPreferenceKey {
    /// 贴图右键菜单顺序（逗号分隔的九项 rawValue；缺键时按 PinMenuAction.defaultOrder 回落）
    public static let contextMenuOrder = "pin.contextMenu.order"
}

// MARK: - 菜单顺序解析（纯函数）

/// 偏好顺序 → 菜单真实顺序
///
/// 三条判据（与 SnipToolBarConfigurationResolver 同风格）：
/// 1. 缺键 / 空串 / 全非法项 → 回落 PinMenuAction.defaultOrder，老配置外观不变；
/// 2. 未知项只丢该项、重复项只留第一次出现，不整份丢弃；
/// 3. 组顺序是常量：即便偏好被手工改成跨组乱序，解析结果仍按 PinMenuAction.groupOrder
///    重新落位 —— 「销毁」永远不会跑到菜单上半部分。
///
/// 读路径不写回：默认值将来变了，没设置过的用户跟着变。
public enum PinMenuOrderResolver {

    /// 全部合法 id（设置页登记顺序用）
    public static var knownIDs: [String] { PinMenuAction.allCases.map(\.rawValue) }

    /// 默认顺序 id（缺键回落用）
    public static var defaultIDs: [String] { PinMenuAction.defaultOrder.map(\.rawValue) }

    /// 把原始顺序整理成合法菜单顺序
    ///
    /// - Parameter raw: 偏好里的原始 id 顺序
    /// - Returns: 组顺序固定、组内按 raw 相对顺序、缺项按默认顺序补尾的完整九项
    public static func normalize(_ raw: [String]) -> [PinMenuAction] {
        // 先按出现顺序收集已知项：未知项丢弃、重复项只留第一次
        var seen = Set<PinMenuAction>()
        var picks: [PinMenuAction] = []
        for id in raw {
            guard let action = PinMenuAction(rawValue: id), seen.insert(action).inserted else { continue }
            picks.append(action)
        }
        // 再逐组落位：组顺序固定，组内按 picks 的相对顺序。
        // 危险组恒按默认顺序（关闭在前、销毁在后），不采纳偏好里的任何换序。
        var result: [PinMenuAction] = []
        for group in PinMenuAction.groupOrder {
            let picked = group.isSortable ? picks.filter { $0.group == group } : []
            var groupSeen = Set(picked)
            var ordered = picked
            for action in PinMenuAction.defaultOrder(in: group) where groupSeen.insert(action).inserted {
                ordered.append(action)
            }
            result.append(contentsOf: ordered)
        }
        return result
    }

    /// 从原始串解析（缺键 / 空串回落到 defaultOrder）
    public static func resolve(orderRaw: String?) -> [PinMenuAction] {
        normalize(SettingsOrderCoding.decode(orderRaw))
    }

    /// 从存储读一份顺序（读路径不写回）
    public static func load(storage: any KeyValueStorage) -> [PinMenuAction] {
        resolve(orderRaw: storage.string(forKey: PinMenuPreferenceKey.contextMenuOrder))
    }

    /// 写一份顺序（调用方传入已整理过的顺序）
    public static func save(_ order: [PinMenuAction], storage: any KeyValueStorage) {
        SettingsOrderStore.save(order.map(\.rawValue),
                                forKey: PinMenuPreferenceKey.contextMenuOrder,
                                storage: storage)
    }

    /// 恢复默认：删键，下次读回落代码默认顺序
    public static func reset(storage: any KeyValueStorage) {
        SettingsOrderStore.reset(forKey: PinMenuPreferenceKey.contextMenuOrder, storage: storage)
    }

    /// 移动一项（-1 上移 / +1 下移）：跨组与危险组一律拒绝，原样返回
    ///
    /// 供通用可排序卡片复用：拒绝时返回同一份顺序，界面不会发生任何位移，
    /// 「排序只能在组内做」这条语义因此不依赖调用方自觉。
    public static func moved(_ ids: [String], id: String, offset: Int) -> [String] {
        guard let action = PinMenuAction(rawValue: id), action.group.isSortable else { return ids }
        let order = resolve(orderRaw: SettingsOrderCoding.encode(ids))
        guard let index = order.firstIndex(of: action) else { return ids }
        let target = index + offset
        guard order.indices.contains(target), order[target].group == action.group else { return ids }
        var next = order
        next.swapAt(index, target)
        return next.map(\.rawValue)
    }

    /// 该位置能否朝 offset 方向移动（行尾按钮的启用判据）
    ///
    /// 判据与 moved 同源：跨组、越界、危险组一律返回 false。
    /// 「销毁」永远拿不到上移按钮，「另存为」也不会被挪到输出组之外。
    public static func canMove(_ ids: [String], index: Int, offset: Int) -> Bool {
        let order = resolve(orderRaw: SettingsOrderCoding.encode(ids))
        guard order.indices.contains(index) else { return false }
        let target = index + offset
        guard order.indices.contains(target) else { return false }
        return order[index].group.isSortable && order[target].group == order[index].group
    }

    /// 可排序卡片用的分组口径（只能组内换序，危险组整体不可动）
    ///
    /// 与通用组件默认的 free 口径唯一的区别是：normalize 走菜单口径（组顺序固定），
    /// 移动与按钮启用都走同源的组内判据。
    public static let movePolicy = SettingsOrderMovePolicy(
        normalize: { ids, _, _ in normalize(ids).map(\.rawValue) },
        move: { ids, id, offset in moved(ids, id: id, offset: offset) },
        canMove: { ids, index, offset in canMove(ids, index: index, offset: offset) })
}
