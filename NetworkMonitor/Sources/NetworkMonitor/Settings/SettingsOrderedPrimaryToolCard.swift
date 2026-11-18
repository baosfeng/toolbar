import AppKit
import NetworkMonitorCore

// MARK: - 常驻工具可排序卡

/// 「常驻工具」卡片 —— 一行 = 显示开关 + 行尾上移 / 下移 + 标题行「恢复默认」
///
/// 与「输出动作」卡（`SettingsOrderedActionCard`）完全同构，复用同一个
/// `SettingsOrderedCardView` 装配器；单独成文件是为了让两个枚举各自可读（同族门禁也按这两族算）。
///
/// 顺序与显隐是两个独立维度，各存各的键、互不覆盖：
/// - 顺序存 `SnipToolBarPreferenceKey.primaryToolOrder`（十二项全序，行常在），
///   只有排序按钮与「恢复默认」读写它；
/// - 显隐仍存 `primaryTools`，开关只增删 `primaryTools`，翻动开关不会挪动任何一行；
/// - 关掉再打开的工具回到它在顺序偏好里的原位，不排到末尾。
///
/// 保底口径与顺序共存：常驻工具只剩一个时工具条上就是那一个（位置按自己的席次，
/// 显隐闸门只管数量、不碰顺序）；可见集合为空时配置层回落到 `SnipTool.primary`。
@MainActor
final class SettingsOrderedPrimaryToolCard {

    /// 卡片本体（调用方摆进页面）
    var card: SettingsCardView { ordered.card }
    /// 标题行「恢复默认」按钮（`finish()` 之后才有值）
    var resetButton: NSButton? { ordered.resetButton }
    /// 显示开关（refresh 与 DEBUG 控件态取证共用）
    private(set) var toggles: [SnipTool: NSSwitch] = [:]

    private let ordered: SettingsOrderedCardView
    /// 读当前配置 / 写回配置：卡片不自己拼偏好，由设置页注入
    private let currentConfig: () -> SnipToolBarConfiguration
    private let applyConfig: (SnipToolBarConfiguration) -> Void

    /// 顺序键与登记行（排序回调里要用，init 阶段还不能引用 self）
    ///
    /// 登记行按声明顺序摆：`SettingsOrderedCardView` 只把登记行交给 normalize，
    /// 缺键时的排布顺序由 `defaultOrder`（SnipTool.primary 打头）决定，
    /// 与 resolver 的回落口径完全一致。
    private static let orderKey = SnipToolBarPreferenceKey.primaryToolOrder
    private static let registeredIDs = SnipTool.allCases.map(\.rawValue)
    private static let defaultOrderIDs = SnipTool.defaultOrder.map(\.rawValue)

    init(storage: any KeyValueStorage,
         currentConfig: @escaping () -> SnipToolBarConfiguration,
         applyConfig: @escaping (SnipToolBarConfiguration) -> Void) {
        self.currentConfig = currentConfig
        self.applyConfig = applyConfig
        let key = Self.orderKey
        self.ordered = SettingsOrderedCardView(orderKey: key,
                                               defaultOrder: Self.defaultOrderIDs,
                                               storage: storage,
                                               onChange: { _ in
            // 排序只改席次：常驻集合原样保留，按新顺序过滤后写回
            var config = currentConfig()
            let order = SettingsOrderStore.order(forKey: key,
                                                 known: Self.registeredIDs,
                                                 defaultOrder: Self.defaultOrderIDs,
                                                 storage: storage)
            config.primaryTools = order.compactMap(SnipTool.init(rawValue:))
                .filter { config.primaryTools.contains($0) }
            applyConfig(config)
        })
    }

    // MARK: - 装配

    /// 逐工具建行（构建页面时调用一次）
    func build() {
        for tool in SnipTool.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(toggleTapped(_:))
            toggle.tag = SnipTool.allCases.firstIndex(of: tool) ?? 0
            toggle.setAccessibilityLabel("常驻工具：\(tool.displayName)")
            toggles[tool] = toggle
            let base = baseSubtitle(for: tool)
            let row = SettingsRowView(title: tool.displayName, subtitle: base)
            row.trailingStack.addArrangedSubview(toggle)
            ordered.addRow(id: tool.rawValue,
                           row: row,
                           accessibilityPrefix: tool.displayName) { [weak row] position in
                row?.update(subtitle: "\(base) · 工具条上第 \(position) 个")
            }
        }
        ordered.finish()
    }

    /// 按偏好灌勾选态
    func refresh(primaryTools: [SnipTool]) {
        for (tool, toggle) in toggles {
            toggle.state = primaryTools.contains(tool) ? .on : .off
        }
    }

    // MARK: - 动作

    /// 只改显隐、不改顺序：新打开的工具回到它在顺序偏好里的原位
    @objc private func toggleTapped(_ sender: NSSwitch) {
        guard SnipTool.allCases.indices.contains(sender.tag) else { return }
        let tool = SnipTool.allCases[sender.tag]
        var config = currentConfig()
        var tools = config.primaryTools
        if tools.contains(tool) {
            // 至少保留一个常驻工具，否则除「更多」以外没有任何画标注的入口
            guard tools.count > 1 else { sender.state = .on; return }
            tools.removeAll { $0 == tool }
        } else {
            tools.append(tool)
        }
        config.primaryTools = tools
        applyConfig(config)
    }

    // MARK: - 文案

    private func baseSubtitle(for tool: SnipTool) -> String {
        tool.isActionTool ? "就地执行的操作" : "落笔生成的标注图元"
    }
}
