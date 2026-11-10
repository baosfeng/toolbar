import Foundation
import NetworkMonitorCore

// MARK: - 时区 / 货币配置与 AppEvents（从 main.swift 拆出）

// MARK: - 时区与货币配置

func runDatabaseConfigTests() {
    print("\n🧪 Testing DatabaseManager...")

    // Test: 时区与货币配置
    do {
        let offset = SqliteTimeZone.offsetModifier
        assertEqual(offset.hasSuffix(" hours"), true, "offset should be 'N hours' format, got: \(offset)")

        // 汇率默认 7.2，可通过注入的 KeyValueStorage 覆盖（不污染 UserDefaults.standard）
        let currencyStorage = UserDefaultsStorage(defaults: UserDefaults(suiteName: "test.currency")!)
        CurrencyConfig.shared.storageOverride = currencyStorage
        currencyStorage.removeObject(forKey: CurrencyConfig.rateOverrideKey)
        assertEqual(CurrencyConfig.shared.usdToCnyRate, 7.2, "default rate 7.2")
        assertEqual(CurrencyConfig.shared.usdToCny(1.0), 7.2, "usdToCny conversion")
        currencyStorage.set(6.5, forKey: CurrencyConfig.rateOverrideKey)
        assertEqual(CurrencyConfig.shared.usdToCnyRate, 6.5, "override rate 6.5")
        assertEqual(CurrencyConfig.shared.usdToCny(1.0), 6.5, "usdToCny conversion with override")
        CurrencyConfig.shared.storageOverride = nil

        print("✅ 时区与货币配置 works")
    }

}

// MARK: - AppEvents 事件总线

func runAppEventsTests() {
    do {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: AppEvents.clipboardChanged,
            object: nil,
            queue: nil
        ) { _ in
            received = true
        }
        AppEvents.postClipboardChanged()
        NotificationCenter.default.removeObserver(observer)
        assertEqual(received, true, "clipboardChanged 事件已发布并接收")

        // 数值单位切档事件：设置页写入偏好后发布，菜单面板靠它立刻重渲染两页数值
        var unitReceived = false
        let unitObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.numberUnitStyleChanged,
            object: nil,
            queue: nil
        ) { _ in
            unitReceived = true
        }
        AppEvents.postNumberUnitStyleChanged()
        NotificationCenter.default.removeObserver(unitObserver)
        assertEqual(unitReceived, true, "numberUnitStyleChanged 事件已发布并接收")

        // 分页可见性变更：设置页写存储后发布，面板靠它重排分段 / 切页 / 收起二级详情
        var panelTabsReceived = false
        let panelTabsObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.panelTabsChanged,
            object: nil,
            queue: nil
        ) { _ in
            panelTabsReceived = true
        }
        AppEvents.postPanelTabsChanged()
        NotificationCenter.default.removeObserver(panelTabsObserver)
        assertEqual(panelTabsReceived, true, "panelTabsChanged 事件已发布并接收")

        // 菜单栏显示偏好变更：设置页写存储后发布，菜单栏靠它重建定时器并重渲染
        var menuBarReceived = false
        let menuBarObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.menuBarDisplayChanged,
            object: nil,
            queue: nil
        ) { _ in
            menuBarReceived = true
        }
        AppEvents.postMenuBarDisplayChanged()
        NotificationCenter.default.removeObserver(menuBarObserver)
        assertEqual(menuBarReceived, true, "menuBarDisplayChanged 事件已发布并接收")

        print("✅ AppEvents 事件总线 works")
    }

}

