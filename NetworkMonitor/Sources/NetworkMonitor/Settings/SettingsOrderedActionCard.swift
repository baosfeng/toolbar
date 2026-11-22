import AppKit
import NetworkMonitorCore

// MARK: - 输出动作可排序卡

/// 「输出动作」卡片 —— 一行 = 显示开关 + 行尾上移 / 下移 + 标题行「恢复默认」
///
/// 从 `SettingsCapturePane` 拆出，与 `SettingsOrderedCardView` 同族（守住单文件门禁）。
///
/// 顺序与显隐是两个独立维度，各存各的键、互不覆盖：
/// - 顺序存 `SnipToolBarPreferenceKey.actionOrder`（全序，四行常在），只有排序按钮与「恢复默认」读写它；
/// - 显隐仍存 `hiddenActions`，开关只增删 `visibleActions`，翻动某个开关不会挪动任何一行；
/// - 关掉再打开的动作回到它在顺序偏好里的原位，不排到末尾。
///
/// 保底口径与顺序共存：可见动作只剩一个时，工具条上就是那一个（位置按自己的席次，
/// 显隐闸门只管数量、不碰顺序）；四个全关时 normalized 固定回落到「复制」——此时顺序偏好
/// 仍是完整四项，重新打开其它动作照旧按偏好顺序上屏。
@MainActor
final class SettingsOrderedActionCard {

    /// 卡片本体（调用方摆进页面）
    var card: SettingsCardView { ordered.card }
    /// 标题行「恢复默认」按钮（`finish()` 之后才有值）
    var resetButton: NSButton? { ordered.resetButton }
    /// 显示开关（refresh 与 DEBUG 控件态取证共用）
    private(set) var toggles: [SnipBarAction: NSSwitch] = [:]

    private let ordered: SettingsOrderedCardView
    /// 读当前配置 / 写回配置：卡片不自己拼偏好，由设置页注入
    private let currentConfig: () -> SnipToolBarConfiguration
    private let applyConfig: (SnipToolBarConfiguration) -> Void

    init(storage: any KeyValueStorage,
         currentConfig: @escaping () -> SnipToolBarConfiguration,
         applyConfig: @escaping (SnipToolBarConfiguration) -> Void) {
        self.currentConfig = currentConfig
        self.applyConfig = applyConfig
        // 排序回调只捕获局部变量：init 阶段还没有 self
        let key = SnipToolBarPreferenceKey.actionOrder
        // 排序卡登记**全部**动作（含撤销 / 重做）：顺序是全序，关掉的项也要占席次
        let ids = SnipBarAction.allOrderCases.map(\.rawValue)
        self.ordered = SettingsOrderedCardView(orderKey: key,
                                               defaultOrder: ids,
                                               storage: storage,
                                               onChange: { _ in
            var config = currentConfig()
            let order = SettingsOrderStore.order(forKey: key,
                                                 known: ids,
                                                 defaultOrder: ids,
                                                 storage: storage)
            config.visibleActions = order.compactMap(SnipBarAction.init(rawValue:))
                .filter { config.visibleActions.contains($0) }
            applyConfig(config)
        })
    }

    // MARK: - 装配

    /// 逐动作建行（构建页面时调用一次）
    func build() {
        for action in SnipBarAction.allOrderCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(toggleTapped(_:))
            toggle.tag = SnipBarAction.allOrderCases.firstIndex(of: action) ?? 0
            toggle.setAccessibilityLabel("工具条动作：\(action.title)")
            toggles[action] = toggle
            let base = baseSubtitle(for: action)
            let row = SettingsRowView(title: action.title, subtitle: base)
            row.trailingStack.addArrangedSubview(toggle)
            ordered.addRow(id: action.rawValue,
                           row: row,
                           accessibilityPrefix: action.title) { [weak row] position in
                row?.update(subtitle: "\(base) · 工具条上第 \(position) 个")
            }
        }
        ordered.finish()
    }

    /// 按偏好灌勾选态
    func refresh(visible: [SnipBarAction]) {
        for (action, toggle) in toggles {
            toggle.state = visible.contains(action) ? .on : .off
        }
    }

    // MARK: - 动作

    /// 只改显隐、不改顺序：新打开的动作回到它在顺序偏好里的原位
    @objc private func toggleTapped(_ sender: NSSwitch) {
        guard SnipBarAction.allOrderCases.indices.contains(sender.tag) else { return }
        let action = SnipBarAction.allOrderCases[sender.tag]
        var config = currentConfig()
        var actions = config.visibleActions
        if actions.contains(action) {
            // 至少保留一个**输出**动作：撤销 / 重做是编辑动作、且可用性还依赖标注栈，
            // 不算出口。只剩它们时工具条上没有任何办法把图交出去，因此同样拦回。
            let remaining = actions.filter { $0 != action }
            guard remaining.contains(where: { !$0.isHiddenByDefault }) else { sender.state = .on; return }
            actions = remaining
        } else {
            actions.append(action)
        }
        config.visibleActions = actions
        applyConfig(config)
    }

    // MARK: - 文案

    private func baseSubtitle(for action: SnipBarAction) -> String {
        if action.isHiddenByDefault {
            // 撤销 / 重做默认不上条：不写明的话用户会以为「开关是开的却没生效」
            return "默认关闭 · 快捷键 \(action.shortcutText)"
        }
        return action.isPrimary ? "强调色主按钮" : "快捷键 \(action.shortcutText)"
    }
}
