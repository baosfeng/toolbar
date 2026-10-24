import Foundation
import NetworkMonitorCore

// MARK: - 窗口检测

func runSnipWindowTests() {
    print("🧪 Testing Snip window hit testing...")

    let desktop = SnipWindowInfo(windowID: 1,
                                 frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                 ownerPID: 100, ownerName: "Finder", title: "")
    let editor = SnipWindowInfo(windowID: 2,
                                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                                ownerPID: 101, ownerName: "Xcode", title: "main.swift")
    let popup = SnipWindowInfo(windowID: 3,
                               frame: CGRect(x: 200, y: 200, width: 200, height: 120),
                               ownerPID: 101, ownerName: "Xcode", title: "弹窗")
    let windows = [popup, editor, desktop]

    // 嵌套窗口取最靠前（列表首位）
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 250, y: 250), in: windows)?.windowID,
                3, "嵌套处命中列表首位窗口")
    // 靠后的小窗口不应抢走前面大窗口的命中
    let behind = SnipWindowInfo(windowID: 4,
                                frame: CGRect(x: 300, y: 300, width: 50, height: 50),
                                ownerPID: 200, ownerName: "Behind", title: "")
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 310, y: 310), in: [editor, behind])?.windowID,
                2, "靠后的小窗口不抢命中")
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 500, y: 500), in: windows)?.windowID,
                2, "只有编辑器覆盖时命中编辑器")
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 1500, y: 900), in: windows)?.windowID,
                1, "空白区命中桌面窗口")
    assertEqual(SnipWindowHitTesting.window(at: CGPoint(x: 5000, y: 5000), in: windows) == nil,
                true, "所有窗口之外不命中")

    // 自身进程与过小窗口被过滤
    let selfWindow = SnipWindowInfo(windowID: 9,
                                    frame: CGRect(x: 0, y: 0, width: 500, height: 400),
                                    ownerPID: 42, ownerName: "NetworkMonitor", title: "")
    let tiny = SnipWindowInfo(windowID: 10,
                              frame: CGRect(x: 10, y: 10, width: 8, height: 8),
                              ownerPID: 100, ownerName: "Finder", title: "")
    let usable = SnipWindowHitTesting.usable(windows: [selfWindow, tiny, editor], excludingPID: 42)
    assertEqual(usable.count, 1, "自身进程与过小窗口被过滤")
    assertEqual(usable.first?.windowID, 2, "保留正常窗口")

    // 状态机：窗口点选直接成立选区
    var state = SnipSelectionState()
    state.select(CGRect(x: 100, y: 100, width: 800, height: 600))
    assertEqual(state.phase, .selected, "窗口点选直接进入已选态")
    assertEqual(state.selection, CGRect(x: 100, y: 100, width: 800, height: 600), "选区等于窗口矩形")

    var reject = SnipSelectionState()
    reject.select(CGRect(x: 0, y: 0, width: 0, height: 0))
    assertEqual(reject.phase, .idle, "零尺寸窗口不成立选区")
}
