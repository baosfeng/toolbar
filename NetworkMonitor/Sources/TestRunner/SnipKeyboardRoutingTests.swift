import Foundation
import NetworkMonitorUI

// MARK: - 截图键盘路由（回归：文字标注打不进字 / 系统快捷键被吞）

func runSnipKeyboardRoutingTests() {
    print("🧪 Testing snip keyboard routing...")

    typealias Routing = SnipKeyboardRouting
    let none = SnipKeyCommandResolver.Modifiers()

    // 覆盖层不在屏：什么都不接管
    assertEqual(Routing.decision(hasTarget: false, isTextEditing: false,
                                 keyCode: 53, characters: nil, modifiers: none), .ignore,
                "无覆盖层时不接管")
    assertEqual(Routing.decision(hasTarget: false, isTextEditing: false,
                                 keyCode: 0, characters: "a", modifiers: none), .ignore,
                "无覆盖层时连字母也不碰")

    // 正在输入文字：所有字符键都要放行，否则文字标注打不进字
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: true,
                                 keyCode: 0, characters: "a", modifiers: none), .passThrough,
                "输入态下 a 放行（否则文字标注打不进字）")
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: true,
                                 keyCode: 1, characters: "s", modifiers: none), .passThrough,
                "输入态下 s 放行")
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: true,
                                 keyCode: 53, characters: nil, modifiers: none), .passThrough,
                "输入态下 Esc 交给输入框自己处理（取消编辑）")

    // 正常截图态：白名单键吞掉
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: false,
                                 keyCode: 36, characters: "\r", modifiers: none), .swallow,
                "回车被覆盖层接管")
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: false,
                                 keyCode: 1, characters: "s", modifiers: .command), .swallow,
                "⌘S 被覆盖层接管")

    // 正常截图态：系统快捷键放行
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: false,
                                 keyCode: 48, characters: "\t", modifiers: .command), .passThrough,
                "⌘Tab 放行")
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: false,
                                 keyCode: 12, characters: "q", modifiers: .command), .passThrough,
                "⌘Q 放行")
    assertEqual(Routing.decision(hasTarget: true, isTextEditing: false,
                                 keyCode: 5, characters: "g", modifiers: none), .passThrough,
                "无关字母放行")

    print("✅ 截图键盘路由测试通过")
}
