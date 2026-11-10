import Foundation
import NetworkMonitorUI

// MARK: - 截图键盘拦截白名单（回归：覆盖层把整个键盘扣住）

func runSnipKeyboardInterceptionTests() {
    print("🧪 Testing snip keyboard interception...")

    typealias Interception = SnipKeyboardInterception
    let none = SnipKeyCommandResolver.Modifiers()

    // 覆盖层有语义的键必须接管
    assertEqual(Interception.shouldIntercept(keyCode: 53, characters: nil, modifiers: none), true, "Esc 接管")
    assertEqual(Interception.shouldIntercept(keyCode: 36, characters: "\r", modifiers: none), true, "回车接管")
    assertEqual(Interception.shouldIntercept(keyCode: 49, characters: " ", modifiers: none), true, "空格接管")
    assertEqual(Interception.shouldIntercept(keyCode: 48, characters: "\t", modifiers: none), true, "Tab 接管")
    assertEqual(Interception.shouldIntercept(keyCode: 123, characters: nil, modifiers: none), true, "方向键接管")
    assertEqual(Interception.shouldIntercept(keyCode: 1, characters: "s", modifiers: .command), true, "⌘S 接管")
    assertEqual(Interception.shouldIntercept(keyCode: 8, characters: "c", modifiers: .command), true, "⌘C 接管")

    // 系统快捷键必须放行（早期实现全吞，⌘Tab / ⌘Q / ⌘空格全失效）
    assertEqual(Interception.shouldIntercept(keyCode: 48, characters: "\t", modifiers: .command), false,
                "⌘Tab 放行，能切到别的 App")
    assertEqual(Interception.shouldIntercept(keyCode: 12, characters: "q", modifiers: .command), false,
                "⌘Q 放行，能退出 App")
    assertEqual(Interception.shouldIntercept(keyCode: 49, characters: " ", modifiers: .command), false,
                "⌘空格 放行，能调出聚焦搜索")
    assertEqual(Interception.shouldIntercept(keyCode: 13, characters: "w", modifiers: .command), false,
                "⌘W 放行")
    assertEqual(Interception.shouldIntercept(keyCode: 9, characters: "v", modifiers: .command), false,
                "⌘V 放行")
    assertEqual(Interception.shouldIntercept(keyCode: 0, characters: "a", modifiers: [.control, .option]), true,
                "⌃⌥A 落在裸键微调语义内（只有 ⌘ 组走命令分支）")
    assertEqual(Interception.shouldIntercept(keyCode: 5, characters: "g", modifiers: [.control, .option]), false,
                "⌃⌥G 放行")

    // 普通字母：只有覆盖层定义的微调 / 取色 / 恢复区域才接管
    assertEqual(Interception.shouldIntercept(keyCode: 0, characters: "a", modifiers: none), true, "裸 a 微调接管")
    assertEqual(Interception.shouldIntercept(keyCode: 5, characters: "g", modifiers: none), false, "无关字母放行")

    // 无字符的按键（功能键 / 输入法候选）不接管
    assertEqual(Interception.shouldIntercept(keyCode: 3, characters: nil, modifiers: none), false, "无字符键放行")

    print("✅ 截图键盘拦截白名单测试通过")
}
