import AppKit
import NetworkMonitorUI

// MARK: - 设置分类装配件（Descriptor + 闭包，App target）

/// 一个设置分类的**装配件** —— 描述符（可测纯值）+ 造页闭包
///
/// 与 `SettingsSectionDescriptor` 的分工（架构契约 §1）：描述符进 UI 库供 TestRunner 断言，
/// 造页闭包带 AppKit 类型只能留 App target。
///
/// 取代改造前 `AppCoordinator+Settings` 里那个 11 条目的工厂字典字面量：
/// 现在每页一条 `register` 声明，新增分类不改任何既有条目。
@MainActor
struct SettingsModule {

    /// 纯值描述符（标题 / 图标 / 副标题 / 快照后缀 / 侧栏分组）
    let descriptor: SettingsSectionDescriptor

    /// 造页 —— 切到该分类时调用（窗口切走即释放，故每次切页都会重建）
    let makePane: () -> SettingsPaneView

    init(descriptor: SettingsSectionDescriptor,
         makePane: @escaping () -> SettingsPaneView) {
        self.descriptor = descriptor
        self.makePane = makePane
    }

    /// 以分类枚举登记（描述符取自 `SettingsSectionCatalog`）
    init(section: SettingsSection, makePane: @escaping () -> SettingsPaneView) {
        self.init(descriptor: section.descriptor, makePane: makePane)
    }
}

// MARK: - 设置分类装配注册表

/// 设置分类装配注册表 —— 组合根一次注册，侧栏 / 切页 / 快照全部从这里读
///
/// 新增一个设置页 = 新建 Pane 文件 + 在 `AppCoordinator+Settings` 里 `register` 一行。
@MainActor
final class SettingsModuleRegistry {

    private var storage: [SettingsSectionID: SettingsModule] = [:]
    private var descriptors = SettingsDescriptorRegistry()

    /// 空注册表（测试 / 未装配场景）
    init() {}

    /// 注册一个分类装配件；同 id 重复注册 = 替换
    @discardableResult
    func register(_ module: SettingsModule) -> Bool {
        let isNew = storage[module.descriptor.id] == nil
        storage[module.descriptor.id] = module
        descriptors.register(module.descriptor)
        return isNew
    }

    /// 全部装配件（按分类目录声明序）
    var all: [SettingsModule] {
        descriptors.all.compactMap { storage[$0.id] }
    }

    /// 按分类查装配件
    func module(for section: SettingsSection) -> SettingsModule? {
        guard let id = SettingsSectionID(rawValue: section.rawValue) else { return nil }
        return storage[id]
    }

    /// 造页（分类未注册返回 nil，窗口据此保留上一页并记一条 warning）
    func makePane(for section: SettingsSection) -> SettingsPaneView? {
        module(for: section)?.makePane()
    }

    /// 注册表自洽判据（空数组 = 自洽）
    func validate() -> [SettingsSectionProblem] { descriptors.validate() }

    /// 全部描述符
    var allDescriptors: [SettingsSectionDescriptor] { descriptors.all }
}
