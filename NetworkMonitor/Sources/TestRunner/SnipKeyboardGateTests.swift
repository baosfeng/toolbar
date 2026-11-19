import Foundation
import NetworkMonitorUI

// MARK: - 截图键盘闸门（回归：文字标注打不进字 / 退格删不掉）
//
// 上一轮的教训：判定函数 SnipKeyboardRouting 是对的、测试也绿着，但编辑态信号
// 从未被写进去（写入点被一行 guard 挡成死代码），真通道永远按「非编辑态」裁决。
// 所以本套件从 **gate 这层状态机**验，而不是再验一遍纯函数：
// 「setEditing(true) 之后退格 / 回车 / Esc 都放行」正是当初漏掉的那一步。

func runSnipKeyboardGateTests() {
    print("🧪 Testing snip keyboard gate（编辑态 × 白名单）...")

    let none = SnipKeyCommandResolver.Modifiers()
    let gate = SnipKeyboardGate()

    // 初始态：没进输入框，白名单键照旧被覆盖层接管
    assertEqual(gate.isEditing, false, "初始不是编辑态")
    assertEqual(gate.decision(hasTarget: true, keyCode: 0, characters: "a", modifiers: none), .swallow,
                "初始态 a 被接管（截图指令）")
    assertEqual(gate.decision(hasTarget: true, keyCode: 51, characters: nil, modifiers: none), .swallow,
                "初始态退格被接管（删除选中标注）")
    assertEqual(gate.decision(hasTarget: true, keyCode: 36, characters: "\r", modifiers: none), .swallow,
                "初始态回车被接管（确认截图）")

    // 进输入框：白名单键必须全部放行，否则就是用户看到的「打不进字 / 删不掉 / 回车直接结束截图」
    gate.setEditing(true)
    assertEqual(gate.isEditing, true, "setEditing(true) 之后闸门打开")
    assertEqual(gate.decision(hasTarget: true, keyCode: 0, characters: "a", modifiers: none), .passThrough,
                "编辑态 a 放行（否则文字标注打不进字）")
    assertEqual(gate.decision(hasTarget: true, keyCode: 51, characters: nil, modifiers: none), .passThrough,
                "编辑态退格放行（否则删不掉字）")
    assertEqual(gate.decision(hasTarget: true, keyCode: 36, characters: "\r", modifiers: none), .passThrough,
                "编辑态回车放行（交给输入框落字，不结束整张截图）")
    assertEqual(gate.decision(hasTarget: true, keyCode: 53, characters: nil, modifiers: none), .passThrough,
                "编辑态 Esc 交给输入框自己处理（取消编辑）")
    assertEqual(gate.decision(hasTarget: true, keyCode: 49, characters: " ", modifiers: none), .passThrough,
                "编辑态空格放行（否则打不出空格，工具条还被隐藏）")
    for arrow in [123, 124, 125, 126] {
        assertEqual(gate.decision(hasTarget: true, keyCode: arrow, characters: nil, modifiers: none),
                    .passThrough,
                    "编辑态方向键 \(arrow) 放行（光标移动，不挪选区）")
    }
    // 白名单里的其余高频键同样要放行（中文拼音必然命中）
    for (code, ch) in [(1, "s"), (2, "d"), (13, "w"), (8, "c"), (15, "r")] {
        assertEqual(gate.decision(hasTarget: true, keyCode: code, characters: ch, modifiers: none),
                    .passThrough,
                    "编辑态 \(ch) 放行")
    }

    // 出输入框：闸门关回去，截图指令恢复
    gate.setEditing(false)
    assertEqual(gate.isEditing, false, "setEditing(false) 之后闸门关闭")
    assertEqual(gate.decision(hasTarget: true, keyCode: 0, characters: "a", modifiers: none), .swallow,
                "退出编辑后 a 回到接管")

    // 守卫：覆盖层不在屏时什么都不接管——哪怕编辑态还亮着
    gate.setEditing(true)
    assertEqual(gate.decision(hasTarget: false, keyCode: 0, characters: "a", modifiers: none), .ignore,
                "无目标时编辑态也 ignore")
    assertEqual(gate.decision(hasTarget: false, keyCode: 51, characters: nil, modifiers: none), .ignore,
                "无目标时退格 ignore")

    // 非白名单键即使在截图中也放行（系统快捷键不能被扣住）
    gate.setEditing(false)
    assertEqual(gate.decision(hasTarget: true, keyCode: 48, characters: "\t", modifiers: .command),
                .passThrough,
                "⌘Tab 始终放行")

    print("✅ snip keyboard gate works（初始吞 / 编辑放 / 关闭复原 / 无目标 ignore）")
}
