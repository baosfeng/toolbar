import Foundation
import NetworkMonitorUI

// MARK: - CLI 页面目标解析

/// `nmcli page` 的目标字符串解析 —— 纯逻辑，断言在 TestRunner 里做，不必起真机
///
/// 这些用例守的是「错的目标必须报错，不能静默落到一个看起来正常的页面」：
/// 猜错 target 会输出一张图，读图的人以为验收过了，实际看的是别的页。
func runCLIPageTargetTests() {
    print("🧪 Testing CLI page target parsing...")

    assertEqual(CLIPageTarget.parse("current"), .current, "current 原样识别")
    assertEqual(CLIPageTarget.parse(""), .current, "空串按 current 处理")
    assertEqual(CLIPageTarget.parse("   "), .current, "纯空白按 current 处理")
    assertEqual(CLIPageTarget.parse("clipboard"), .clipboard, "剪贴板浮层")
    assertEqual(CLIPageTarget.parse("clipboard-panel"), .clipboard, "剪贴板浮层别名")
    assertEqual(CLIPageTarget.parse("menu"), .menu(tabID: nil), "菜单面板不指定分页")
    assertEqual(CLIPageTarget.parse("menu.token"), .menu(tabID: "token"), "菜单面板指定分页")
    assertEqual(CLIPageTarget.parse("MENU.Token"), .menu(tabID: "token"), "大小写不敏感")
    assertEqual(CLIPageTarget.parse("settings"), .settings(sectionID: nil), "设置窗口默认分类")
    assertEqual(CLIPageTarget.parse("settings.clipboard"), .settings(sectionID: "clipboard"), "设置窗口指定分类")
    assertEqual(CLIPageTarget.parse("nope"), nil, "不认识的写法必须报错，不许猜")

    // rawValue 与 parse 必须互为逆运算：nmcli 侧打日志 / 回执都用 rawValue
    let roundTrip: [CLIPageTarget] = [.current, .clipboard, .menu(tabID: nil),
                                      .menu(tabID: "token"), .settings(sectionID: nil),
                                      .settings(sectionID: "clipboard")]
    for target in roundTrip {
        assertEqual(CLIPageTarget.parse(target.rawValue), target, "rawValue 往返：\(target.rawValue)")
    }

    assertEqual(CLIPageTarget.current.needsOpening, false, "current 不该触发打开页面")
    assertEqual(CLIPageTarget.clipboard.needsOpening, true, "剪贴板浮层需要先打开")

    // 常量表必须覆盖 App 层会用到的那几个 id（漂移时这里先红）
    assertContains(CLIPageChannel.knownMenuTabIDs.joined(separator: ","), "token", "菜单分页表含 token")
    assertContains(CLIPageChannel.knownSettingsSectionIDs.joined(separator: ","), "clipboard",
                   "设置分类表含 clipboard")
}
