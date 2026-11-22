import Foundation
import NetworkMonitorCore

// MARK: - 工具条动作的两个显隐键（老四项 / 扩展动作分开落盘）

/// 与 `SnipToolBarOrderTests` 分文件：那边守顺序键与显隐解耦，这里只守
/// 「`hiddenActions` 只管老四项、新增动作走 `utilityActions`」这一条兼容契约。
/// 拆开也是为了守住单文件 15 KiB 门禁（两块断言回答不同问题）。
func runSnipToolBarActionPreferenceTests() {
    print("🧪 Testing snip toolbar action visibility keys...")

    // MARK: 两个显隐键分开落盘（老键格式不变、新键缺省=关）

    let actionStorage = InMemoryStorage()
    // 老配置形态：只有旧键、没有 utilityActions，读出来仍是老四项
    SnipToolBarConfigurationResolver.persist(
        SnipToolBarConfiguration(visibleActions: [.cancel, .copy, .save, .pin]),
        storage: actionStorage)
    assertEqual(actionStorage.string(forKey: SnipToolBarPreferenceKey.hiddenActions), "",
                "老四项全开时 hiddenActions 写空串（与改动前同格式）")
    assertEqual(actionStorage.string(forKey: SnipToolBarPreferenceKey.utilityActions), "",
                "没启用扩展动作时 utilityActions 写空串")
    actionStorage.removeObject(forKey: SnipToolBarPreferenceKey.utilityActions)
    assertEqual(SnipToolBarConfigurationResolver.load(storage: actionStorage).visibleActions,
                [.cancel, .copy, .save, .pin],
                "utilityActions 缺键（老配置）时读回来仍是老四项")

    // 用户主动打开撤销 / 重做：落进新键，老键内容不受影响
    SnipToolBarConfigurationResolver.persist(
        SnipToolBarConfiguration(visibleActions: [.cancel, .copy, .save, .pin, .undo, .redo]),
        storage: actionStorage)
    assertEqual(actionStorage.string(forKey: SnipToolBarPreferenceKey.hiddenActions), "",
                "启用扩展动作不改写 hiddenActions")
    assertEqual(actionStorage.string(forKey: SnipToolBarPreferenceKey.utilityActions), "undo,redo",
                "启用的扩展动作按声明顺序落盘")
    assertEqual(SnipToolBarConfigurationResolver.load(storage: actionStorage).visibleActions,
                [.cancel, .copy, .save, .pin, .undo, .redo],
                "往返后撤销 / 重做仍在（排在老四项之后）")

    // 再关掉一个老项：老键写回该项名，扩展动作保持启用
    SnipToolBarConfigurationResolver.persist(
        SnipToolBarConfiguration(visibleActions: [.copy, .save, .pin, .undo]),
        storage: actionStorage)
    assertEqual(actionStorage.string(forKey: SnipToolBarPreferenceKey.hiddenActions), "cancel",
                "关掉的老项按项名落进 hiddenActions")
    assertEqual(actionStorage.string(forKey: SnipToolBarPreferenceKey.utilityActions), "undo",
                "关掉重做后 utilityActions 只剩撤销")
    assertEqual(SnipToolBarConfigurationResolver.load(storage: actionStorage).visibleActions,
                [.copy, .save, .pin, .undo], "往返后可见集合与写入一致")

    print("✅ 工具条动作显隐键测试通过")
}
