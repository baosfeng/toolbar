import AppKit
import NetworkMonitorCore

// MARK: - 排序按钮

/// 行尾排序按钮 —— 自带行 id 与方向
///
/// 不用 `tag` 反查：tag 只能存整数，重排后索引会漂移；也不看 `hashValue`（跨启动不稳定）。
final class SettingsOrderButton: NSButton {

    /// 该按钮所属行 id
    let rowID: String
    /// -1 上移 / +1 下移
    let offset: Int

    private let plainTitle: String

    init(title: String,
         rowID: String,
         offset: Int,
         accessibilityPrefix: String,
         target: AnyObject?,
         action: Selector) {
        self.plainTitle = title
        self.rowID = rowID
        self.offset = offset
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setButtonType(.momentaryChange)
        isBordered = false
        setAccessibilityLabel(accessibilityPrefix + " " + title)
        applyAppearance(enabled: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 首项不能再上移、末项不能再下移：禁用并转三级色（不隐藏，保持行内宽度稳定）
    ///
    /// 可用 / 禁用两档都走主题令牌：系统强调色不随三套主题变，
    /// 会让「上移 / 下移」在石墨、米白主题下仍是系统蓝。
    func applyAppearance(enabled: Bool) {
        isEnabled = enabled
        SettingsLinkButton.setTitle(plainTitle, on: self,
                                    color: enabled ? SettingsTheme.accent : SettingsTheme.textTertiary)
    }
}

// MARK: - 可排序卡片

/// 可排序卡片的装配器 —— 收敛三件重复劳动：
/// 行尾「上移 / 下移」、行副标题「第 N 项」、卡片标题行右侧「恢复默认」
///
/// 用法：
/// 1. 构造（orderKey + defaultOrder + storage）
/// 2. 逐项 `addRow(id:row:accessibilityPrefix:setPosition:)`，setPosition 负责把「第 N 项」写进行副标题
/// 3. `finish()` 按偏好顺序把行摆进 `card`；把 `resetButton` 交给
///    `SettingsPageStack.addCard(_:sectionTitle:trailingAccessory:)`
///
/// 顺序只存 stable id 字符串，不用 Int：枚举中间插入 case 时旧顺序不会错位。
@MainActor
final class SettingsOrderedCardView {

    /// 卡片本体（调用方放进页面）
    let card = SettingsCardView()

    /// 「恢复默认」按钮 —— 由调用方摆到卡片标题行右侧；仅在 `finish()` 之后可用
    private(set) var resetButton: NSButton?

    /// 行移动 / 恢复默认之后回调（调用方据此做额外副作用，例如发 AppEvents 让菜单栏重排）
    private let onChange: (([String]) -> Void)?

    private let orderKey: String
    private let defaultOrder: [String]
    private let storage: any KeyValueStorage

    /// 登记顺序（normalize 的兜底判据）
    private var registered: [String] = []
    private var rows: [String: SettingsRowView] = [:]
    private var positionSetters: [String: (Int) -> Void] = [:]
    private var moveButtons: [String: (up: SettingsOrderButton, down: SettingsOrderButton)] = [:]
    /// 当前生效顺序（已过 normalize）
    private var order: [String] = []
    private var isBuilt = false

    init(orderKey: String,
         defaultOrder: [String],
         storage: any KeyValueStorage,
         onChange: (([String]) -> Void)? = nil) {
        self.orderKey = orderKey
        self.defaultOrder = defaultOrder
        self.storage = storage
        self.onChange = onChange
    }

    // MARK: - 装配

    /// 登记一行（登记顺序不影响最终摆放顺序，最终顺序以偏好为准）
    ///
    /// - Parameters:
    ///   - id: 稳定 id（枚举 rawValue）
    ///   - row: 行视图；排序按钮追加到它的 `trailingStack` 末尾
    ///   - accessibilityPrefix: 排序按钮可读名前缀（行名，便于读屏分辨）
    ///   - setPosition: 写「第 N 项」副标题的回调，N 从 1 开始
    func addRow(id: String,
                row: SettingsRowView,
                accessibilityPrefix: String,
                setPosition: @escaping (Int) -> Void) {
        registered.append(id)
        rows[id] = row
        positionSetters[id] = setPosition

        let up = SettingsOrderButton(title: "上移", rowID: id, offset: -1,
                                     accessibilityPrefix: accessibilityPrefix,
                                     target: self, action: #selector(moveTapped(_:)))
        let down = SettingsOrderButton(title: "下移", rowID: id, offset: 1,
                                       accessibilityPrefix: accessibilityPrefix,
                                       target: self, action: #selector(moveTapped(_:)))
        row.trailingStack.addArrangedSubview(up)
        row.trailingStack.addArrangedSubview(down)
        moveButtons[id] = (up, down)
    }

    /// 按偏好顺序摆行并生成「恢复默认」按钮（只生效一次）
    func finish() {
        guard !isBuilt else { return }
        isBuilt = true
        order = SettingsOrderStore.order(forKey: orderKey,
                                         known: registered,
                                         defaultOrder: defaultOrder,
                                         storage: storage)
        layoutRows()
        resetButton = SettingsLinkButton.make("恢复默认", target: self, action: #selector(resetTapped),
                                             color: SettingsTheme.textSecondary)
        resetButton?.setAccessibilityLabel("恢复默认顺序")
    }

    // MARK: - 动作

    @objc private func moveTapped(_ sender: SettingsOrderButton) {
        let moved = SettingsOrderStore.moved(order, id: sender.rowID, offset: sender.offset)
        guard moved != order else { return }
        order = moved
        SettingsOrderStore.save(moved, forKey: orderKey, storage: storage)
        layoutRows()
        onChange?(moved)
    }

    @objc private func resetTapped() {
        SettingsOrderStore.reset(forKey: orderKey, storage: storage)
        order = SettingsOrderStore.order(forKey: orderKey,
                                         known: registered,
                                         defaultOrder: defaultOrder,
                                         storage: storage)
        layoutRows()
        onChange?(order)
    }

    // MARK: - 摆放

    /// 整卡重建：清掉旧行再按 order 逐行加回（行间分隔线由卡片自己补，挪单行会把线搞乱）
    private func layoutRows() {
        card.removeAllRows()
        for (index, id) in order.enumerated() {
            guard let row = rows[id] else { continue }
            card.addRow(row)
            positionSetters[id]?(index + 1)
            moveButtons[id]?.up.applyAppearance(enabled: index > 0)
            moveButtons[id]?.down.applyAppearance(enabled: index < order.count - 1)
        }
    }
}
