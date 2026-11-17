import Foundation

// MARK: - 工具条偏好键名

/// 截图工具条自定义的偏好键名
///
/// 键名集中在这里：设置页写入、覆盖层读取、测试断言共用同一份定义，
/// 避免「设置页写的键没人读」这类「设了不生效」的老毛病。
public enum SnipToolBarPreferenceKey {
    /// 文字提示档（iconOnly / hover / always）
    public static let labelMode = "snip.toolbar.labelMode"
    /// 组顺序（逗号分隔的组名）
    public static let groupOrder = "snip.toolbar.groupOrder"
    /// 被隐藏的组（逗号分隔的组名）
    public static let hiddenGroups = "snip.toolbar.hiddenGroups"
    /// 一级常驻工具（逗号分隔的工具名）
    public static let primaryTools = "snip.toolbar.primaryTools"
    /// 被隐藏的动作按钮（逗号分隔的动作名）
    public static let hiddenActions = "snip.toolbar.hiddenActions"
    /// 输出动作的排列顺序（逗号分隔的动作名；缺键时按 SnipBarAction.defaultOrder 回落）
    public static let actionOrder = "snip.toolbar.actionOrder"
    /// 工具条位置（auto / below / above）
    public static let placement = "snip.toolbar.placement"
}

// MARK: - 逗号列表编码

/// 偏好里的逗号分隔列表 —— 编码与解码同源，坏数据不会让设置页读崩
public enum SnipToolBarListCoding {

    /// 解码：按逗号切分、去空白、丢空项
    public static func decode(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 编码：按给定顺序拼成逗号分隔串
    public static func encode(_ values: [String]) -> String {
        values.joined(separator: ",")
    }
}

// MARK: - 配置解析

/// 偏好 → 工具条配置（纯函数）
///
/// 判据收进 Core 而不是散在视图与设置页里：
/// 1. 缺键一律回落到默认配置，读路径不写回（默认值将来变了，没设置过的用户跟着变）；
/// 2. 写了不合法的组名 / 工具名只丢弃该项，不整份丢弃；
/// 3. 结果必须能上屏（至少一组、一个工具、一个动作），因此统一过一遍 normalized。
public enum SnipToolBarConfigurationResolver {

    /// 解析一份完整配置
    ///
    /// - Parameters:
    ///   - labelModeRaw: 文字提示档原始值（未知或缺失 → 悬停提示）
    ///   - groupOrderRaw: 组顺序原始串（缺失 → allCases 顺序）
    ///   - hiddenGroupsRaw: 被隐藏组的原始串
    ///   - primaryToolsRaw: 常驻工具原始串（缺失 → SnipTool.primary）
    ///   - hiddenActionsRaw: 被隐藏动作的原始串
    ///   - actionOrderRaw: 输出动作顺序原始串（缺失 → defaultOrder，老配置外观不变）
    public static func resolve(labelModeRaw: String?,
                               groupOrderRaw: String?,
                               hiddenGroupsRaw: String?,
                               primaryToolsRaw: String?,
                               hiddenActionsRaw: String?,
                               placementRaw: String? = nil,
                               actionOrderRaw: String? = nil) -> SnipToolBarConfiguration {
        let mode = labelModeRaw.flatMap(SnipToolBarLabelMode.init(rawValue:)) ?? .hover
        let placement = placementRaw.flatMap(SnipToolBarPlacement.init(rawValue:)) ?? .auto

        let orderNames = SnipToolBarListCoding.decode(groupOrderRaw)
        let order = orderNames.isEmpty ? SnipToolBarGroup.allCases
            : SnipToolBarGroup.order(from: orderNames)

        let hiddenGroupNames = Set(SnipToolBarListCoding.decode(hiddenGroupsRaw))
        let visibleGroups = Set(SnipToolBarGroup.allCases.filter {
            !hiddenGroupNames.contains($0.rawValue)
        })

        // 常驻工具按存储里的顺序映射（未知名字丢弃），顺序即工具条上的排列顺序
        let toolNames = SnipToolBarListCoding.decode(primaryToolsRaw)
        let tools = toolNames.isEmpty
            ? SnipTool.primary
            : toolNames.compactMap { SnipTool(rawValue: $0) }

        // 动作先按偏好顺序排（去未知 / 去重 / 缺项补尾），再按显隐过滤：
        // 顺序键只决定先后，显隐仍由 hiddenActions 决定，两件事互不影响
        let hiddenActionNames = Set(SnipToolBarListCoding.decode(hiddenActionsRaw))
        let actionOrderNames = SettingsOrderCoding.normalize(
            SnipToolBarListCoding.decode(actionOrderRaw),
            known: SnipBarAction.defaultOrder.map(\.rawValue),
            defaultOrder: SnipBarAction.defaultOrder.map(\.rawValue))
        let actions = actionOrderNames
            .compactMap { SnipBarAction(rawValue: $0) }
            .filter { !hiddenActionNames.contains($0.rawValue) }

        return SnipToolBarConfiguration(labelMode: mode,
                                        groupOrder: order,
                                        visibleGroups: visibleGroups,
                                        primaryTools: tools,
                                        visibleActions: actions,
                                        placement: placement)
    }

    /// 把配置写回偏好（设置页与覆盖层回写共用）
    ///
    /// 顺序键 `actionOrder` 不在这里写：它归 `SettingsOrderStore` 独占（排序按钮 save / 恢复默认 reset）。
    /// 显隐与顺序是两个独立维度——若在此按「可见动作」回写顺序，关掉的动作会丢席次、
    /// 重新打开时排到末尾。顺序键缺省时 resolve 回落 defaultOrder，老配置外观不变。
    public static func persist(_ config: SnipToolBarConfiguration, storage: any KeyValueStorage) {
        storage.set(config.labelMode.rawValue, forKey: SnipToolBarPreferenceKey.labelMode)
        storage.set(SnipToolBarListCoding.encode(config.groupOrder.map(\.rawValue)),
                    forKey: SnipToolBarPreferenceKey.groupOrder)
        let hiddenGroups = SnipToolBarGroup.allCases
            .filter { !config.visibleGroups.contains($0) }
            .map(\.rawValue)
        storage.set(SnipToolBarListCoding.encode(hiddenGroups),
                    forKey: SnipToolBarPreferenceKey.hiddenGroups)
        storage.set(SnipToolBarListCoding.encode(config.primaryTools.map(\.rawValue)),
                    forKey: SnipToolBarPreferenceKey.primaryTools)
        let hiddenActions = SnipBarAction.allCases
            .filter { !config.visibleActions.contains($0) }
            .map(\.rawValue)
        storage.set(SnipToolBarListCoding.encode(hiddenActions),
                    forKey: SnipToolBarPreferenceKey.hiddenActions)
        storage.set(config.placement.rawValue, forKey: SnipToolBarPreferenceKey.placement)
    }

    /// 从存储读一份配置（缺键回落默认，读路径不写回）
    public static func load(storage: any KeyValueStorage) -> SnipToolBarConfiguration {
        resolve(labelModeRaw: storage.string(forKey: SnipToolBarPreferenceKey.labelMode),
                groupOrderRaw: storage.string(forKey: SnipToolBarPreferenceKey.groupOrder),
                hiddenGroupsRaw: storage.string(forKey: SnipToolBarPreferenceKey.hiddenGroups),
                primaryToolsRaw: storage.string(forKey: SnipToolBarPreferenceKey.primaryTools),
                hiddenActionsRaw: storage.string(forKey: SnipToolBarPreferenceKey.hiddenActions),
                placementRaw: storage.string(forKey: SnipToolBarPreferenceKey.placement),
                actionOrderRaw: storage.string(forKey: SnipToolBarPreferenceKey.actionOrder))
    }
}
