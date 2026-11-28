import AppKit
import Foundation
import NetworkMonitorUI

// MARK: - 设置行图标白名单（回归：写错符号名 = 静默没有图标）

/// 图标是「按白名单精确匹配」的：标题文案改了、符号名写错了，界面上只是少一个图标，
/// 不会有任何报错。所以这里逐条解析符号名，把错字挡在测试里。
func runSettingsRowIconMapTests() {
    print("🧪 Testing 设置行图标白名单...")

    let map = SettingsRowIconMap.icons
    assertEqual(map.isEmpty, false, "白名单不能为空")

    for (title, symbol) in map {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        assertEqual(image != nil, true, "符号名可解析：\(title) → \(symbol)")
    }

    // 命中：登记过的标题取到符号
    assertEqual(SettingsRowIconMap.symbol(for: "开机自启动"), "power", "登记过的标题取到符号")
    assertEqual(SettingsRowIconMap.symbol(for: "鼠标滚轮平滑") != nil, true, "滚轮行有图标")

    // 未登记：必须返回 nil（白名单不猜，避免图标撒谎）
    assertEqual(SettingsRowIconMap.symbol(for: "某个没登记的行") == nil, true, "未登记的标题返回 nil")
}
