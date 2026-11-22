import Foundation

// MARK: - 贴图菜单偏好键名

/// 贴图右键菜单的偏好键名
///
/// 与截图工具条同理：键名只在这里定义一次，设置页写入、贴图窗读取、测试断言共用，
/// 避免「设置页写了一个键、贴图窗读的是另一个键」这类「设了不生效」的故障。
public enum PinMenuPreferenceKey {
    /// 贴图右键菜单顺序（逗号分隔的 rawValue；缺键时按 PinMenuAction.defaultOrder 回落）
    public static let contextMenuOrder = "pin.contextMenu.order"
}

// MARK: - 菜单顺序解析（纯函数）

/// 偏好顺序 → 菜单真实顺序
///
/// 四条判据（与 SnipToolBarConfigurationResolver 同风格）：
/// 1. 缺键 / 空串 / 全非法项 → 回落 PinMenuAction.defaultOrder，老配置外观不变；
/// 2. 已知项严格按偏好顺序落位，跨组换序也生效（用户要求「全部放开可调」）；
/// 3. 未知项只丢该项、重复项只留第一次出现，缺失项按默认顺序补尾；
/// 4. 旧偏好（组内换序时代的顺序串）无需迁移：它本来就是一个合法的全序，
///    直接按同一套规则读出来即可，只是从此允许跨组；
/// 5. 新增项（灰度 / 反色 / 棋盘底）对老偏好就是「缺失项」，按第 3 条补到末尾 ——
///    用户已排好的前几项逐位不动，新功能只是追加在菜单尾部，不是插进中间。
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
    /// - Returns: 完整菜单项（顺序即最终菜单顺序）
    public static func normalize(_ raw: [String]) -> [PinMenuAction] {
        // 按出现顺序收集已知项：未知项丢弃、重复项只留第一次
        var seen = Set<PinMenuAction>()
        var result: [PinMenuAction] = []
        for id in raw {
            guard let action = PinMenuAction(rawValue: id), seen.insert(action).inserted else { continue }
            result.append(action)
        }
        // 缺失项（老偏好里没有的新增项）按默认顺序补到末尾，既不丢也不打乱已有排序
        for action in PinMenuAction.defaultOrder where seen.insert(action).inserted {
            result.append(action)
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

    /// 移动一项（-1 上移 / +1 下移）：跨组同样允许，只拒越界
    ///
    /// 供通用可排序卡片复用：拒绝时返回同一份顺序，界面不会发生任何位移。
    public static func moved(_ ids: [String], id: String, offset: Int) -> [String] {
        guard let action = PinMenuAction(rawValue: id) else { return ids }
        let order = resolve(orderRaw: SettingsOrderCoding.encode(ids))
        guard let index = order.firstIndex(of: action) else { return ids }
        let target = index + offset
        guard order.indices.contains(target) else { return ids }
        var next = order
        next.swapAt(index, target)
        return next.map(\.rawValue)
    }

    /// 该位置能否朝 offset 方向移动（行尾按钮的启用判据）
    ///
    /// 判据与 moved 同源：只看越界，不看分组 —— 任意排列都是合法菜单。
    public static func canMove(_ ids: [String], index: Int, offset: Int) -> Bool {
        let order = resolve(orderRaw: SettingsOrderCoding.encode(ids))
        guard order.indices.contains(index) else { return false }
        return order.indices.contains(index + offset)
    }

    /// 可排序卡片用的口径（整列自由换序）
    ///
    /// 与通用组件默认的 free 口径唯一区别：normalize 走菜单口径（未知项丢弃、缺项按
    /// defaultOrder 补尾），移动与按钮启用则与 free 一致地只判越界。
    public static let movePolicy = SettingsOrderMovePolicy(
        normalize: { ids, _, _ in normalize(ids).map(\.rawValue) },
        move: { ids, id, offset in moved(ids, id: id, offset: offset) },
        canMove: { ids, index, offset in canMove(ids, index: index, offset: offset) })
}
