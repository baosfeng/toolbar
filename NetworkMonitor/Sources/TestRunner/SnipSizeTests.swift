import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 尺寸输入与长宽比锁定

func runSnipSizeTests() {
    print("🧪 Testing Snip size input & aspect lock...")

    // 文本解析
    assertEqual(SnipSizeInput.parse("800x600"), CGSize(width: 800, height: 600), "小写 x 分隔")
    assertEqual(SnipSizeInput.parse("800X600"), CGSize(width: 800, height: 600), "大写 X 分隔")
    assertEqual(SnipSizeInput.parse("800*600"), CGSize(width: 800, height: 600), "星号分隔")
    assertEqual(SnipSizeInput.parse("800,600"), CGSize(width: 800, height: 600), "逗号分隔")
    assertEqual(SnipSizeInput.parse("800×600"), CGSize(width: 800, height: 600), "乘号分隔")
    assertEqual(SnipSizeInput.parse(" 800 600 "), CGSize(width: 800, height: 600), "空格分隔")
    assertEqual(SnipSizeInput.parse("800") == nil, true, "缺一维返回 nil")
    assertEqual(SnipSizeInput.parse("0x600") == nil, true, "零宽返回 nil")
    assertEqual(SnipSizeInput.parse("-800x600") == nil, true, "负值返回 nil")
    assertEqual(SnipSizeInput.parse("abc") == nil, true, "非数字返回 nil")
    assertEqual(SnipSizeInput.parse("") == nil, true, "空串返回 nil")

    // 长宽比锁定：2:1 选区，右下角拉伸
    let origin = CGRect(x: 100, y: 100, width: 200, height: 100)
    let dragged = SnipAspectLock.lockedResize(handle: .bottomRight,
                                              origin: origin,
                                              dx: 100,
                                              dy: 10)
    assertEqual(dragged.width, 300, "宽度跟随水平位移")
    assertEqual(dragged.height, 150, "高度按 2:1 自动跟随")
    assertEqual(dragged.origin, CGPoint(x: 100, y: 100), "左上角固定")

    // 左上角拉伸：右下角固定
    let topLeft = SnipAspectLock.lockedResize(handle: .topLeft,
                                               origin: origin,
                                               dx: -100,
                                               dy: 0)
    assertEqual(topLeft.maxX, 300, "右下角固定 X")
    assertEqual(topLeft.maxY, 200, "右下角固定 Y")
    assertEqual(topLeft.width / topLeft.height, 2, "角度拉伸仍保持 2:1")

    // 只拖上边：宽度按比例跟随
    let top = SnipAspectLock.lockedResize(handle: .top, origin: origin, dx: 0, dy: -50)
    assertEqual(top.height, 150, "上边拉伸高度 +50")
    assertEqual(top.width, 300, "宽度按 2:1 跟随")
    assertEqual(top.maxY, 200, "下边固定")

    // 反向收缩不会出现负尺寸
    let shrunk = SnipAspectLock.lockedResize(handle: .bottomRight, origin: origin, dx: -1000, dy: -1000)
    assertEqual(shrunk.width >= 1 && shrunk.height >= 1, true, "收缩后仍为正尺寸")

    // move 不影响比例
    let moved = SnipAspectLock.lockedResize(handle: .move, origin: origin, dx: 10, dy: 20)
    assertEqual(moved, origin.offsetBy(dx: 10, dy: 20), "移动不改变尺寸")

    // 状态机：锁定比例调整
    var state = SnipSelectionState()
    state.select(origin)
    state.beginAdjust(.bottomRight, at: CGPoint(x: 300, y: 200))
    state.adjust(to: CGPoint(x: 400, y: 210), lockingAspect: true)
    state.endAdjust()
    assertEqual(state.rect.width, 300, "状态机锁定比例：宽度")
    assertEqual(state.rect.height, 150, "状态机锁定比例：高度")
}
