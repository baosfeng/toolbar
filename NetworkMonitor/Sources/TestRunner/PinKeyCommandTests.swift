import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - P0-3 / P0-4 贴图窗键位与点击语义

func runPinKeyCommandTests() {
    print("🧪 Testing pin key command resolver...")

    typealias Resolver = PinKeyCommandResolver
    let none = SnipKeyCommandResolver.Modifiers()
    let cmd = SnipKeyCommandResolver.Modifiers(command: true)
    let cmdShift = SnipKeyCommandResolver.Modifiers(command: true, shift: true)
    let ctrl = SnipKeyCommandResolver.Modifiers(control: true)

    // Esc 关闭、⇧Esc 销毁（既有行为不能被本轮改动破坏）
    assertEqual(Resolver.resolve(keyCode: 53, characters: nil, modifiers: none), .close, "Esc 关闭贴图")
    assertEqual(Resolver.resolve(keyCode: 53, characters: nil, modifiers: [.shift]), .destroy,
                "⇧Esc 销毁贴图")

    // P0-3：⌘W 关闭（官方「只对贴图有效」表里明写）
    assertEqual(Resolver.resolve(keyCode: 13, characters: "w", modifiers: cmd), .close, "⌘W 关闭贴图")
    assertEqual(Resolver.resolve(keyCode: 13, characters: nil, modifiers: cmd), .close,
                "⌘W 缺字符时按字符兜底也要关闭")
    assertEqual(Resolver.resolve(keyCode: 13, characters: "w", modifiers: none), nil,
                "裸 w 不接管")

    // 旋转与镜像：既有键位保持
    assertEqual(Resolver.resolve(keyCode: 18, characters: "1", modifiers: none), .rotateClockwise, "1 顺时针")
    assertEqual(Resolver.resolve(keyCode: 19, characters: "2", modifiers: none), .rotateCounterClockwise, "2 逆时针")
    assertEqual(Resolver.resolve(keyCode: 20, characters: "3", modifiers: none), .mirrorHorizontal, "3 水平镜像")
    assertEqual(Resolver.resolve(keyCode: 21, characters: "4", modifiers: none), .mirrorVertical, "4 垂直镜像")
    assertEqual(Resolver.resolve(keyCode: 23, characters: "5", modifiers: none), .thumbnail, "5 缩略图")

    // P0-4：+ / - 缩放，⌃+ / ⌃- 调透明度
    assertEqual(Resolver.resolve(keyCode: 24, characters: "+", modifiers: none),
                .zoom(factor: Resolver.zoomStep), "+ 放大")
    assertEqual(Resolver.resolve(keyCode: 27, characters: "-", modifiers: none),
                .zoom(factor: 1 / Resolver.zoomStep), "- 缩小")
    assertEqual(Resolver.resolve(keyCode: 24, characters: "=", modifiers: none),
                .zoom(factor: Resolver.zoomStep), "主键盘 = 与 + 同义（免按 ⇧）")
    assertEqual(Resolver.resolve(keyCode: 24, characters: "+", modifiers: ctrl),
                .alphaDelta(Resolver.alphaStep), "⌃+ 提高不透明度")
    assertEqual(Resolver.resolve(keyCode: 27, characters: "-", modifiers: ctrl),
                .alphaDelta(-Resolver.alphaStep), "⌃- 降低不透明度")

    // ⌘ 组合里只有 ⌘W 归贴图窗，其余放行给系统
    assertEqual(Resolver.resolve(keyCode: 12, characters: "q", modifiers: cmd), nil, "⌘Q 不归贴图窗")
    assertEqual(Resolver.resolve(keyCode: 18, characters: "1", modifiers: cmd), nil, "⌘1 不归贴图窗")
    assertEqual(Resolver.resolve(keyCode: 1, characters: "s", modifiers: cmdShift), nil, "⌘⇧S 不归贴图窗")
    assertEqual(Resolver.resolve(keyCode: 0, characters: "a", modifiers: none), nil, "裸 a 不归贴图窗")

    // P0-3：左键双击关闭 / 中键重置 / 单击仍拖动
    typealias Click = PinClickIntent
    assertEqual(Click.outcome(buttonNumber: 0, clickCount: 1), .dragWindow, "左键单击仍是拖动窗口")
    assertEqual(Click.outcome(buttonNumber: 0, clickCount: 2), .closeWindow, "左键双击关闭贴图")
    assertEqual(Click.outcome(buttonNumber: 0, clickCount: 3), .closeWindow, "三连击也按双击处理")
    assertEqual(Click.outcome(buttonNumber: 2, clickCount: 1), .resetSizeAndAlpha,
                "中键单击重置 100% 大小与不透明")
    assertEqual(Click.outcome(buttonNumber: 2, clickCount: 2), .resetSizeAndAlpha,
                "中键连击仍只重置")
    assertEqual(Click.outcome(buttonNumber: 1, clickCount: 1), .dragWindow, "右键不归点击判定（走右键菜单）")

    print("✅ 贴图窗键位与点击语义测试通过")
}
