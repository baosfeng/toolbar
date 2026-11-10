import Foundation
import NetworkMonitorUI

// MARK: - 截图覆盖层键位解析（回归：⌘S / ⌘A 被裸字母分支吃掉）

func runSnipKeyCommandTests() {
    print("🧪 Testing snip key command resolver...")

    typealias Resolver = SnipKeyCommandResolver
    let none = Resolver.Modifiers()

    // 无修饰键的基础键位
    assertEqual(Resolver.resolve(keyCode: 53, characters: nil, modifiers: none), .cancel, "Esc 取消")
    assertEqual(Resolver.resolve(keyCode: 36, characters: "\r", modifiers: none), .confirm, "回车确认")
    assertEqual(Resolver.resolve(keyCode: 76, characters: "\r", modifiers: none), .confirm, "小键盘回车确认")
    assertEqual(Resolver.resolve(keyCode: 50, characters: "`", modifiers: none), .toggleCursor, "反引号切指针")
    assertEqual(Resolver.resolve(keyCode: 49, characters: " ", modifiers: none), .toggleToolBar, "空格显隐工具条")
    assertEqual(Resolver.resolve(keyCode: 43, characters: ",", modifiers: none), .historyOlder, "逗号回退历史")
    assertEqual(Resolver.resolve(keyCode: 47, characters: ".", modifiers: none), .historyNewer, "句号前进历史")
    assertEqual(Resolver.resolve(keyCode: 48, characters: "\t", modifiers: none), .toggleWindowDetection, "Tab 切窗口检测")

    // 方向键微调
    assertEqual(Resolver.resolve(keyCode: 123, characters: nil, modifiers: none), .nudge(dx: -1, dy: 0), "← 左移")
    assertEqual(Resolver.resolve(keyCode: 124, characters: nil, modifiers: none), .nudge(dx: 1, dy: 0), "→ 右移")
    assertEqual(Resolver.resolve(keyCode: 125, characters: nil, modifiers: none), .nudge(dx: 0, dy: 1), "↓ 下移")
    assertEqual(Resolver.resolve(keyCode: 126, characters: nil, modifiers: none), .nudge(dx: 0, dy: -1), "↑ 上移")

    // 修饰键组合优先于裸字母（这条是本次回归的核心）
    assertEqual(Resolver.resolve(keyCode: 1, characters: "s", modifiers: .command), .save(quick: false),
                "⌘S 保存，而不是「选区向下挪 1 点」")
    assertEqual(Resolver.resolve(keyCode: 1, characters: "s", modifiers: [.command, .shift]), .save(quick: true),
                "⌘⇧S 快速保存")
    assertEqual(Resolver.resolve(keyCode: 0, characters: "a", modifiers: .command), .selectAll,
                "⌘A 全选整屏，而不是「选区向左挪 1 点」")
    assertEqual(Resolver.resolve(keyCode: 8, characters: "c", modifiers: .command), .copyImage, "⌘C 复制")
    assertEqual(Resolver.resolve(keyCode: 17, characters: "t", modifiers: .command), .pin, "⌘T 贴顶")
    assertEqual(Resolver.resolve(keyCode: 15, characters: "r", modifiers: .command), .rotateSelectedText, "⌘R 旋转选中文字")
    assertEqual(Resolver.resolve(keyCode: 6, characters: "z", modifiers: .command), .undo, "⌘Z 撤销")
    assertEqual(Resolver.resolve(keyCode: 6, characters: "z", modifiers: [.command, .shift]), .redo, "⌘⇧Z 重做")

    // 裸字母：微调与取色
    assertEqual(Resolver.resolve(keyCode: 0, characters: "a", modifiers: none), .nudge(dx: -1, dy: 0), "裸 a 仍是微调")
    assertEqual(Resolver.resolve(keyCode: 2, characters: "d", modifiers: none), .nudge(dx: 1, dy: 0), "裸 d 微调")
    assertEqual(Resolver.resolve(keyCode: 13, characters: "w", modifiers: none), .nudge(dx: 0, dy: -1), "裸 w 微调")
    assertEqual(Resolver.resolve(keyCode: 1, characters: "s", modifiers: none), .nudge(dx: 0, dy: 1), "裸 s 微调")
    assertEqual(Resolver.resolve(keyCode: 8, characters: "c", modifiers: none), .copyColor, "裸 c 取色")
    assertEqual(Resolver.resolve(keyCode: 15, characters: "r", modifiers: none), .restoreLastSelection, "裸 r 恢复上次选区")

    // 无关按键不当成命令（不能吞掉别的键）
    assertEqual(Resolver.resolve(keyCode: 9, characters: "v", modifiers: .command), .none, "⌘V 不归覆盖层处理")
    assertEqual(Resolver.resolve(keyCode: 5, characters: "g", modifiers: none), .none, "无关字母返回 none")

    // 修饰键构造：界面层逐键翻译，未指定的键（CapsLock 等）不进入解析口径
    assertEqual(Resolver.Modifiers(command: true, shift: true),
                [.command, .shift], "⌘⇧ 正确映射")
    assertEqual(Resolver.Modifiers(control: true, option: true),
                Resolver.Modifiers([.control, .option]), "⌃⌥ 正确映射")
    assertEqual(Resolver.Modifiers(), Resolver.Modifiers([]), "无修饰键为空集")
    assertEqual(Resolver.Modifiers(command: true), Resolver.Modifiers([.command]), "单独 ⌘ 正确映射")

    print("✅ 截图键位解析测试通过")
}
